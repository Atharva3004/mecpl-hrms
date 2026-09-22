<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\Attendance\PunchInRequest;
use App\Http\Requests\Attendance\PunchOutRequest;
use App\Models\AttendancePunchModel;
use App\Models\AttendanceSessionModel;
use App\Models\BranchModel;
use App\Support\Geo;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;

class AttendancePunchController extends Controller
{
    public function punchIn(PunchInRequest $request): JsonResponse
    {
        $employee = $request->user();
        $employee->load('companyDetails');

        // Block if geofence attendance is not enabled for this employee
        if (($employee->companyDetails->geofence_attendance ?? 'No') !== 'Yes') {
            return response()->json([
                'status'     => false,
                'error_code' => 'GEOFENCE_NOT_ENABLED',
                'message'    => 'Geofence attendance is not enabled for your account.',
            ], 403);
        }

        $branchId = $employee->companyDetails->br_id ?? null;
        $branch = $branchId ? BranchModel::find($branchId) : null;

        if (!$branch) {
            return response()->json([
                'status'  => false,
                'message' => 'No branch assigned.',
            ], 422);
        }

        [$inside, $distance] = $this->resolveGeofence($branch, $request);

        // Store selfie
        $selfiePath = $this->storeSelfie($request, $employee->id);

        $now = now();

        // Transaction with lockForUpdate to prevent race condition on concurrent punch-in
        $result = DB::transaction(function () use ($request, $employee, $branch, $selfiePath, $inside, $distance, $now) {
            // Lock active sessions for this employee to prevent concurrent punch-in
            $existing = AttendanceSessionModel::where('employee_id', $employee->id)
                ->where('status', 'active')
                ->lockForUpdate()
                ->first();
            if ($existing) {
                return ['error' => 'SESSION_ALREADY_OPEN', 'session' => $existing];
            }

            // Check if employee already completed a punch cycle today
            $todayIST = \Carbon\Carbon::now('Asia/Kolkata')->toDateString();
            $completedSession = AttendanceSessionModel::where('employee_id', $employee->id)
                ->where('status', 'closed')
                ->whereDate('date', $todayIST)
                ->lockForUpdate()
                ->first();
            if ($completedSession) {
                return ['error' => 'ALREADY_PUNCHED_TODAY', 'session' => $completedSession];
            }

            // Is this the first punch today?
            $isFirstOfDay = !AttendancePunchModel::where('employee_id', $employee->id)
                ->whereDate('punched_at', $now->toDateString())
                ->exists();

            $session = AttendanceSessionModel::create([
                'employee_id' => $employee->id,
                'branch_id'   => $branch->id,
                'date'        => $now->toDateString(),
                'started_at'  => $now,
                'status'      => 'active',
            ]);

            $punch = AttendancePunchModel::create([
                'employee_id'        => $employee->id,
                'branch_id'          => $branch->id,
                'session_id'         => $session->id,
                'type'               => 'in',
                'punched_at'         => $now,
                'client_captured_at' => $request->input('client_captured_at'),
                'latitude'           => $request->input('latitude'),
                'longitude'          => $request->input('longitude'),
                'accuracy_m'         => $request->input('accuracy_m'),
                'address'            => $request->input('address'),
                'inside_geofence'    => $inside,
                'distance_m'         => $distance,
                'selfie_path'        => $selfiePath,
                'device_info'        => $request->input('device_info'),
                'is_first_of_day'    => $isFirstOfDay,
            ]);

            $session->update(['punch_in_id' => $punch->id]);

            return compact('session', 'punch', 'isFirstOfDay');
        });

        // Handle errors returned from inside the transaction
        if (isset($result['error'])) {
            if ($result['error'] === 'SESSION_ALREADY_OPEN') {
                return response()->json([
                    'status'     => false,
                    'error_code' => 'SESSION_ALREADY_OPEN',
                    'message'    => 'You already have an open session.',
                    'data'       => [
                        'session_id' => $result['session']->id,
                        'started_at' => $result['session']->started_at,
                    ],
                ], 409);
            }

            return response()->json([
                'status'     => false,
                'error_code' => 'ALREADY_PUNCHED_TODAY',
                'message'    => 'You have already completed today\'s punch-in and punch-out.',
                'data'       => [
                    'session_id'       => $result['session']->id,
                    'started_at'       => $result['session']->started_at,
                    'ended_at'         => $result['session']->ended_at,
                    'duration_seconds' => $result['session']->duration_seconds,
                ],
            ], 409);
        }

        return response()->json([
            'status'  => true,
            'message' => 'Punch-in recorded.',
            'data'    => [
                'session_id'      => $result['session']->id,
                'punch_id'        => $result['punch']->id,
                'server_time'     => $now->toIso8601String(),
                'is_first_of_day' => $result['isFirstOfDay'],
                'geofence' => [
                    'inside'     => $inside,
                    'distance_m' => $distance,
                    'radius_m'   => $branch->geofence_radius_m,
                ],
            ],
        ]);
    }

    public function punchOut(PunchOutRequest $request): JsonResponse
    {
        $employee = $request->user();
        $session  = AttendanceSessionModel::find($request->input('session_id'));

        if (!$session || $session->employee_id !== $employee->id) {
            return response()->json([
                'status'  => false,
                'message' => 'Session not found.',
            ], 404);
        }
        if ($session->status !== 'active') {
            return response()->json([
                'status'  => false,
                'message' => 'Session is not active.',
            ], 409);
        }

        $branch = $session->branch;
        [$inside, $distance] = $this->resolveGeofence($branch, $request);

        $selfiePath = $this->storeSelfie($request, $employee->id);
        $now = now();

        $result = DB::transaction(function () use ($request, $session, $employee, $branch, $selfiePath, $inside, $distance, $now) {
            // Clear previous is_last_of_day flags for today
            AttendancePunchModel::where('employee_id', $employee->id)
                ->whereDate('punched_at', $now->toDateString())
                ->where('type', 'out')
                ->update(['is_last_of_day' => false]);

            $punch = AttendancePunchModel::create([
                'employee_id'        => $employee->id,
                'branch_id'          => $branch->id,
                'session_id'         => $session->id,
                'type'               => 'out',
                'punched_at'         => $now,
                'client_captured_at' => $request->input('client_captured_at'),
                'latitude'           => $request->input('latitude'),
                'longitude'          => $request->input('longitude'),
                'accuracy_m'         => $request->input('accuracy_m'),
                'address'            => $request->input('address'),
                'inside_geofence'    => $inside,
                'distance_m'         => $distance,
                'selfie_path'        => $selfiePath,
                'device_info'        => $request->input('device_info'),
                'is_last_of_day'     => true,
            ]);

            $duration = $now->diffInSeconds($session->started_at);

            $session->update([
                'punch_out_id'     => $punch->id,
                'ended_at'         => $now,
                'duration_seconds' => $duration,
                'status'           => 'closed',
            ]);

            return compact('session', 'punch', 'duration');
        });

        return response()->json([
            'status'  => true,
            'message' => 'Punch-out recorded.',
            'data'    => [
                'session_id'       => $result['session']->id,
                'punch_id'         => $result['punch']->id,
                'duration_seconds' => $result['duration'],
                'ping_count'       => $result['session']->ping_count,
                'is_last_of_day'   => true,
                'geofence' => [
                    'inside'     => $inside,
                    'distance_m' => $distance,
                    'radius_m'   => $branch->geofence_radius_m,
                ],
            ],
        ]);
    }

    private function resolveGeofence($branch, $request): array
    {
        if (!$branch || !$branch->hasGeofence()) {
            return [true, null]; // No fence configured -> always "inside"
        }
        $distance = (int) round(Geo::haversine(
            (float) $branch->latitude,
            (float) $branch->longitude,
            (float) $request->input('latitude'),
            (float) $request->input('longitude'),
        ));
        $inside = $distance <= (int) $branch->geofence_radius_m;
        return [$inside, $distance];
    }

    private function storeSelfie($request, int $employeeId): string
    {
        $now = now();
        $dir = sprintf('attendance/%s/%s', $now->format('Y'), $now->format('m'));
        $filename = sprintf('%d_%d.jpg', $employeeId, $now->timestamp);
        return $request->file('selfie')->storeAs($dir, $filename, 'public');
    }
}
