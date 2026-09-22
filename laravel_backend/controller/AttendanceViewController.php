<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AttendanceLocationPingModel;
use App\Models\AttendancePunchModel;
use App\Models\AttendanceSessionModel;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class AttendanceViewController extends Controller
{
    public function today(Request $request): JsonResponse
    {
        $employee = $request->user();
        $today    = now()->toDateString();

        $active = AttendanceSessionModel::where('employee_id', $employee->id)
            ->where('status', 'active')
            ->first();

        $lastPing = null;
        if ($active) {
            $p = AttendanceLocationPingModel::where('session_id', $active->id)
                ->latest('captured_at')
                ->first();
            if ($p) {
                $lastPing = [
                    'latitude'    => $p->latitude,
                    'longitude'   => $p->longitude,
                    'captured_at' => $p->captured_at->toIso8601String(),
                ];
            }
        }

        $punches = AttendancePunchModel::where('employee_id', $employee->id)
            ->whereDate('punched_at', $today)
            ->orderBy('punched_at')
            ->get()
            ->map(fn ($p) => [
                'session_id'      => $p->session_id,
                'type'            => $p->type,
                'punched_at'      => $p->punched_at->toIso8601String(),
                'latitude'        => $p->latitude,
                'longitude'       => $p->longitude,
                'accuracy_m'      => $p->accuracy_m,
                'address'         => $p->address,
                'selfie_url'      => $p->selfie_url,
                'inside_geofence' => $p->inside_geofence,
                'distance_m'      => $p->distance_m,
            ]);

        $sessionsToday = AttendanceSessionModel::where('employee_id', $employee->id)
            ->whereDate('date', $today)
            ->get();
        $totalSeconds = (int) $sessionsToday->sum('duration_seconds');

        return response()->json([
            'status' => true,
            'data'   => [
                'active_session' => $active ? [
                    'session_id' => $active->id,
                    'started_at' => $active->started_at->toIso8601String(),
                    'ping_count' => $active->ping_count,
                    'last_ping'  => $lastPing,
                ] : null,
                'punches'        => $punches,
                'total_seconds'  => $totalSeconds,
            ],
        ]);
    }

    public function live(Request $request): JsonResponse
    {
        $query = AttendanceSessionModel::with([
                'employee:id,emp_name',
                'employee.companyDetails:id,emp_id,emp_code,br_id',
                'branch:id,branch_name',
            ])
            ->where('status', 'active');

        if ($request->filled('branch_id')) {
            $query->where('branch_id', $request->integer('branch_id'));
        }

        $sessions = $query->limit($request->integer('limit', 100))->get();

        $data = $sessions->map(function ($s) {
            $lastPing = AttendanceLocationPingModel::where('session_id', $s->id)
                ->latest('captured_at')
                ->first();

            return [
                'session_id' => $s->id,
                'employee'   => [
                    'id'       => $s->employee->id ?? null,
                    'emp_name' => $s->employee->emp_name ?? 'Unknown',
                    'emp_code' => $s->employee->companyDetails->emp_code ?? '',
                ],
                'branch'     => $s->branch,
                'started_at' => $s->started_at->toIso8601String(),
                'ping_count' => $s->ping_count,
                'last_ping'  => $lastPing ? [
                    'latitude'        => $lastPing->latitude,
                    'longitude'       => $lastPing->longitude,
                    'inside_geofence' => $lastPing->inside_geofence,
                    'captured_at'     => $lastPing->captured_at->toIso8601String(),
                ] : null,
            ];
        });

        return response()->json(['status' => true, 'data' => $data]);
    }

    public function history(Request $request): JsonResponse
    {
        $request->validate([
            'date'    => 'required|date_format:Y-m-d',
            'user_id' => 'nullable|integer',
        ]);

        $user = $request->user();
        $user->load('companyDetails');
        $targetEmployeeId = $user->id;

        // Admin can view another employee's history
        if ($request->filled('user_id')) {
            $isAdmin = ($user->companyDetails->role ?? '') === 'ADMIN';
            if (!$isAdmin) {
                return response()->json(['status' => false, 'message' => 'Admin access required to view other employees.'], 403);
            }
            $targetEmployeeId = $request->integer('user_id');
        }

        $date = $request->input('date');

        // Match by `date` column OR by `started_at` date (fallback for sessions
        // where the date column may be null or mismatched due to timezone)
        $sessions = AttendanceSessionModel::with([
                'punches' => fn ($q) => $q->orderBy('punched_at'),
                'pings'   => fn ($q) => $q->orderBy('captured_at'),
            ])
            ->where('employee_id', $targetEmployeeId)
            ->where(function ($q) use ($date) {
                $q->whereDate('date', $date)
                  ->orWhereDate('started_at', $date);
            })
            ->orderBy('started_at')
            ->get();

        $sessionData = $sessions->map(function ($s) {
            return [
                'session_id'       => $s->id,
                'started_at'       => $s->started_at->toIso8601String(),
                'ended_at'         => $s->ended_at ? $s->ended_at->toIso8601String() : null,
                'duration_seconds' => $s->duration_seconds,
                'status'           => $s->status,
                'punches'          => $s->punches->map(fn ($p) => [
                    'session_id'      => $p->session_id,
                    'type'            => $p->type,
                    'punched_at'      => $p->punched_at->toIso8601String(),
                    'latitude'        => $p->latitude,
                    'longitude'       => $p->longitude,
                    'accuracy_m'      => $p->accuracy_m,
                    'address'         => $p->address,
                    'selfie_url'      => $p->selfie_url,
                    'inside_geofence' => $p->inside_geofence,
                    'distance_m'      => $p->distance_m,
                ]),
                'pings'            => $s->pings->map(fn ($p) => [
                    'latitude'        => $p->latitude,
                    'longitude'       => $p->longitude,
                    'captured_at'     => $p->captured_at->toIso8601String(),
                    'inside_geofence' => $p->inside_geofence,
                    'accuracy_m'      => $p->accuracy_m,
                    'selfie_url'      => $p->selfie_url,
                ]),
            ];
        });

        $totalSeconds = (int) $sessions->sum('duration_seconds');

        return response()->json([
            'status' => true,
            'data'   => [
                'date'          => $date,
                'total_seconds' => $totalSeconds,
                'sessions'      => $sessionData,
            ],
        ]);
    }

    public function timeline(Request $request, int $sessionId): JsonResponse
    {
        $session = AttendanceSessionModel::with([
                'punchIn',
                'punchOut',
                'pings' => fn ($q) => $q->orderBy('captured_at'),
            ])
            ->findOrFail($sessionId);

        // Allow self or admin
        $user = $request->user();
        $user->load('companyDetails');
        $isAdmin = ($user->companyDetails->role ?? '') === 'ADMIN';

        if ($session->employee_id !== $user->id && !$isAdmin) {
            return response()->json(['status' => false, 'message' => 'Forbidden.'], 403);
        }

        return response()->json([
            'status' => true,
            'data'   => [
                'session'   => [
                    'id'          => $session->id,
                    'employee_id' => $session->employee_id,
                    'started_at'  => $session->started_at->toIso8601String(),
                    'ended_at'    => $session->ended_at ? $session->ended_at->toIso8601String() : null,
                    'status'      => $session->status,
                ],
                'punch_in'  => $session->punchIn ? [
                    'latitude'        => $session->punchIn->latitude,
                    'longitude'       => $session->punchIn->longitude,
                    'punched_at'      => $session->punchIn->punched_at->toIso8601String(),
                    'selfie_url'      => $session->punchIn->selfie_url,
                    'inside_geofence' => $session->punchIn->inside_geofence,
                ] : null,
                'punch_out' => $session->punchOut ? [
                    'latitude'        => $session->punchOut->latitude,
                    'longitude'       => $session->punchOut->longitude,
                    'punched_at'      => $session->punchOut->punched_at->toIso8601String(),
                    'selfie_url'      => $session->punchOut->selfie_url,
                    'inside_geofence' => $session->punchOut->inside_geofence,
                ] : null,
                'pings'     => $session->pings->map(fn ($p) => [
                    'latitude'        => $p->latitude,
                    'longitude'       => $p->longitude,
                    'captured_at'     => $p->captured_at->toIso8601String(),
                    'inside_geofence' => $p->inside_geofence,
                    'accuracy_m'      => $p->accuracy_m,
                    'selfie_url'      => $p->selfie_url,
                ]),
            ],
        ]);
    }
}
