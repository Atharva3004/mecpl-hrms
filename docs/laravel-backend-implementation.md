# Laravel Backend Implementation Guide — Attendance, Geofencing & Location Tracking

Standalone reference for the Laravel developer. Everything needed to implement the backend is here — migrations, models, controllers, routes, requests, policies, console commands, and example HTTP calls. No access to the Flutter project required.

**Target stack**: Laravel 10+ (11 preferred), PHP 8.2+, MySQL 8, Laravel Sanctum, local disk storage.

---

## Table of contents

1. [Scope](#1-scope)
2. [Prerequisites](#2-prerequisites)
3. [Database migrations](#3-database-migrations)
4. [Eloquent models](#4-eloquent-models)
5. [FormRequest validation](#5-formrequest-validation)
6. [Controllers](#6-controllers)
7. [Policies & authorization](#7-policies--authorization)
8. [Routes](#8-routes)
9. [Storage & selfie handling](#9-storage--selfie-handling)
10. [Console command — 180-day ping purge](#10-console-command--180-day-ping-purge)
11. [Rate limiting](#11-rate-limiting)
12. [Example requests (curl)](#12-example-requests-curl)
13. [Testing checklist](#13-testing-checklist)
14. [Deployment notes](#14-deployment-notes)

---

## 1. Scope

Build the server side of a punch-in/punch-out + geofencing + 30-minute location-tracking feature for a mobile HRMS app.

**Business rules:**
- Every punch (in OR out) uploads a selfie + GPS coordinates.
- The backend computes distance from the employee's assigned branch.
- **Out-of-fence punches are accepted** but flagged `inside_geofence=0` for reporting.
- A "session" = one punch-in + the matching punch-out; all the 30-minute location pings between them belong to that session.
- Multiple in/out sessions per day are allowed (e.g., lunch break).
- Only one session per employee can be `active` at a time.
- Location pings are purged after **180 days**. Punches (with selfies) are kept forever.
- Admin role has a live-attendance view.

**Assumption**: an `employees` table exists with `id`, `name`, `branch_id` (FK), and Laravel Sanctum tokens are already working for auth. Adjust column names if yours differ.

---

## 2. Prerequisites

```bash
composer require laravel/sanctum
php artisan vendor:publish --provider="Laravel\Sanctum\SanctumServiceProvider"
php artisan migrate

# Expose selfies publicly
php artisan storage:link

# Ensure config/filesystems.php 'public' disk points to storage/app/public (default).
```

`.env`:
```env
APP_URL=https://hrms.mecpl.in
FILESYSTEM_DISK=public
```

Confirm `User` (or `Employee`) model uses `HasApiTokens`:
```php
use Laravel\Sanctum\HasApiTokens;
class Employee extends Authenticatable {
    use HasApiTokens;
    // ...
}
```

---

## 3. Database migrations

Create four migration files with `php artisan make:migration`. Run in the order below.

### 3.1 `2026_04_20_000001_add_geofence_columns_to_branches_table.php`

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::table('branches', function (Blueprint $table) {
            $table->decimal('latitude', 10, 7)->nullable()->after('branch_name');
            $table->decimal('longitude', 10, 7)->nullable()->after('latitude');
            $table->unsignedSmallInteger('geofence_radius_m')->nullable()->after('longitude');
        });
    }

    public function down(): void
    {
        Schema::table('branches', function (Blueprint $table) {
            $table->dropColumn(['latitude', 'longitude', 'geofence_radius_m']);
        });
    }
};
```

### 3.2 `2026_04_20_000002_create_attendance_sessions_table.php`

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('attendance_sessions', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('employee_id');
            $table->unsignedBigInteger('branch_id');
            $table->date('date');
            $table->unsignedBigInteger('punch_in_id')->nullable();  // set immediately after the punch-in row is created
            $table->unsignedBigInteger('punch_out_id')->nullable();
            $table->timestamp('started_at');
            $table->timestamp('ended_at')->nullable();
            $table->unsignedInteger('duration_seconds')->nullable();
            $table->unsignedInteger('ping_count')->default(0);
            $table->enum('status', ['active', 'closed', 'force_closed'])->default('active');
            $table->timestamps();

            $table->foreign('employee_id')->references('id')->on('employees')->cascadeOnDelete();
            $table->foreign('branch_id')->references('id')->on('branches')->restrictOnDelete();

            $table->index(['employee_id', 'status']);
            $table->index(['employee_id', 'date']);
            $table->index(['branch_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('attendance_sessions');
    }
};
```

### 3.3 `2026_04_20_000003_create_attendance_punches_table.php`

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('attendance_punches', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('employee_id');
            $table->unsignedBigInteger('branch_id');
            $table->unsignedBigInteger('session_id');
            $table->enum('type', ['in', 'out']);
            $table->timestamp('punched_at');
            $table->timestamp('client_captured_at')->nullable();
            $table->decimal('latitude', 10, 7);
            $table->decimal('longitude', 10, 7);
            $table->float('accuracy_m')->nullable();
            $table->string('address', 500)->nullable();
            $table->boolean('inside_geofence');
            $table->unsignedInteger('distance_m')->nullable();
            $table->string('selfie_path', 255);
            $table->json('device_info')->nullable();
            $table->boolean('is_first_of_day')->default(false);
            $table->boolean('is_last_of_day')->default(false);
            $table->timestamps();

            $table->foreign('employee_id')->references('id')->on('employees')->cascadeOnDelete();
            $table->foreign('branch_id')->references('id')->on('branches')->restrictOnDelete();
            $table->foreign('session_id')->references('id')->on('attendance_sessions')->cascadeOnDelete();

            $table->index(['employee_id', 'punched_at']);
            $table->index('session_id');
            $table->index(['branch_id', 'punched_at']);
        });

        // Now that punches exist, add the FKs on sessions (circular dep resolved).
        Schema::table('attendance_sessions', function (Blueprint $table) {
            $table->foreign('punch_in_id')->references('id')->on('attendance_punches')->nullOnDelete();
            $table->foreign('punch_out_id')->references('id')->on('attendance_punches')->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('attendance_sessions', function (Blueprint $table) {
            $table->dropForeign(['punch_in_id']);
            $table->dropForeign(['punch_out_id']);
        });
        Schema::dropIfExists('attendance_punches');
    }
};
```

### 3.4 `2026_04_20_000004_create_attendance_location_pings_table.php`

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('attendance_location_pings', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('session_id');
            $table->unsignedBigInteger('employee_id');
            $table->decimal('latitude', 10, 7);
            $table->decimal('longitude', 10, 7);
            $table->float('accuracy_m')->nullable();
            $table->string('address', 500)->nullable();
            $table->boolean('inside_geofence');
            $table->unsignedInteger('distance_m')->nullable();
            $table->unsignedTinyInteger('battery_pct')->nullable();
            $table->timestamp('captured_at');
            $table->timestamp('received_at');
            $table->boolean('is_queued')->default(false);
            $table->timestamp('created_at')->useCurrent();

            $table->foreign('session_id')->references('id')->on('attendance_sessions')->cascadeOnDelete();
            $table->foreign('employee_id')->references('id')->on('employees')->cascadeOnDelete();

            $table->index(['employee_id', 'captured_at']);
            $table->index(['session_id', 'captured_at']);
            $table->index('captured_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('attendance_location_pings');
    }
};
```

Run all four:
```bash
php artisan migrate
```

---

## 4. Eloquent models

Put these under `app/Models/`.

### 4.1 `Branch.php` (add geofence accessors to existing model)

```php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Branch extends Model
{
    protected $fillable = ['branch_name', 'latitude', 'longitude', 'geofence_radius_m'];

    protected $casts = [
        'latitude'          => 'float',
        'longitude'         => 'float',
        'geofence_radius_m' => 'integer',
    ];

    public function hasGeofence(): bool
    {
        return $this->latitude !== null
            && $this->longitude !== null
            && $this->geofence_radius_m !== null;
    }
}
```

### 4.2 `AttendanceSession.php`

```php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class AttendanceSession extends Model
{
    protected $fillable = [
        'employee_id', 'branch_id', 'date',
        'punch_in_id', 'punch_out_id',
        'started_at', 'ended_at', 'duration_seconds',
        'ping_count', 'status',
    ];

    protected $casts = [
        'date'             => 'date',
        'started_at'       => 'datetime',
        'ended_at'         => 'datetime',
        'duration_seconds' => 'integer',
        'ping_count'       => 'integer',
    ];

    public function employee(): BelongsTo
    {
        return $this->belongsTo(Employee::class);
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }

    public function punches(): HasMany
    {
        return $this->hasMany(AttendancePunch::class, 'session_id');
    }

    public function pings(): HasMany
    {
        return $this->hasMany(AttendanceLocationPing::class, 'session_id');
    }

    public function punchIn(): BelongsTo
    {
        return $this->belongsTo(AttendancePunch::class, 'punch_in_id');
    }

    public function punchOut(): BelongsTo
    {
        return $this->belongsTo(AttendancePunch::class, 'punch_out_id');
    }
}
```

### 4.3 `AttendancePunch.php`

```php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AttendancePunch extends Model
{
    protected $fillable = [
        'employee_id', 'branch_id', 'session_id',
        'type', 'punched_at', 'client_captured_at',
        'latitude', 'longitude', 'accuracy_m', 'address',
        'inside_geofence', 'distance_m',
        'selfie_path', 'device_info',
        'is_first_of_day', 'is_last_of_day',
    ];

    protected $casts = [
        'punched_at'         => 'datetime',
        'client_captured_at' => 'datetime',
        'latitude'           => 'float',
        'longitude'          => 'float',
        'accuracy_m'         => 'float',
        'inside_geofence'    => 'boolean',
        'distance_m'         => 'integer',
        'device_info'        => 'array',
        'is_first_of_day'    => 'boolean',
        'is_last_of_day'     => 'boolean',
    ];

    public function session(): BelongsTo
    {
        return $this->belongsTo(AttendanceSession::class, 'session_id');
    }

    public function getSelfieUrlAttribute(): ?string
    {
        return $this->selfie_path
            ? asset('storage/' . ltrim($this->selfie_path, '/'))
            : null;
    }
}
```

### 4.4 `AttendanceLocationPing.php`

```php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AttendanceLocationPing extends Model
{
    public $timestamps = false; // we only have created_at; no updated_at

    protected $fillable = [
        'session_id', 'employee_id',
        'latitude', 'longitude', 'accuracy_m', 'address',
        'inside_geofence', 'distance_m', 'battery_pct',
        'captured_at', 'received_at', 'is_queued',
    ];

    protected $casts = [
        'latitude'        => 'float',
        'longitude'       => 'float',
        'accuracy_m'      => 'float',
        'inside_geofence' => 'boolean',
        'distance_m'      => 'integer',
        'battery_pct'     => 'integer',
        'captured_at'     => 'datetime',
        'received_at'     => 'datetime',
        'is_queued'       => 'boolean',
    ];

    public function session(): BelongsTo
    {
        return $this->belongsTo(AttendanceSession::class, 'session_id');
    }
}
```

---

## 5. FormRequest validation

`app/Http/Requests/Attendance/`:

### 5.1 `PunchInRequest.php`

```php
namespace App\Http\Requests\Attendance;

use Illuminate\Foundation\Http\FormRequest;

class PunchInRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user() !== null;
    }

    public function rules(): array
    {
        return [
            'selfie'             => 'required|file|mimes:jpg,jpeg,png|max:2048',
            'latitude'           => 'required|numeric|between:-90,90',
            'longitude'          => 'required|numeric|between:-180,180',
            'accuracy_m'         => 'nullable|numeric|min:0|max:10000',
            'address'            => 'nullable|string|max:500',
            'client_captured_at' => 'required|date',
            'device_info'        => 'nullable|json',
        ];
    }
}
```

### 5.2 `PunchOutRequest.php`

```php
namespace App\Http\Requests\Attendance;

use Illuminate\Foundation\Http\FormRequest;

class PunchOutRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user() !== null;
    }

    public function rules(): array
    {
        return [
            'session_id'         => 'required|integer|exists:attendance_sessions,id',
            'selfie'             => 'required|file|mimes:jpg,jpeg,png|max:2048',
            'latitude'           => 'required|numeric|between:-90,90',
            'longitude'          => 'required|numeric|between:-180,180',
            'accuracy_m'         => 'nullable|numeric|min:0|max:10000',
            'address'            => 'nullable|string|max:500',
            'client_captured_at' => 'required|date',
            'device_info'        => 'nullable|json',
        ];
    }
}
```

### 5.3 `LocationPingRequest.php`

```php
namespace App\Http\Requests\Attendance;

use Illuminate\Foundation\Http\FormRequest;

class LocationPingRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user() !== null;
    }

    public function rules(): array
    {
        return [
            'session_id'  => 'required|integer|exists:attendance_sessions,id',
            'latitude'    => 'required|numeric|between:-90,90',
            'longitude'   => 'required|numeric|between:-180,180',
            'accuracy_m'  => 'nullable|numeric|min:0|max:10000',
            'address'     => 'nullable|string|max:500',
            'battery_pct' => 'nullable|integer|between:0,100',
            'captured_at' => 'required|date',
        ];
    }
}
```

### 5.4 `LocationPingBatchRequest.php`

```php
namespace App\Http\Requests\Attendance;

use Illuminate\Foundation\Http\FormRequest;

class LocationPingBatchRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user() !== null;
    }

    public function rules(): array
    {
        return [
            'pings'                 => 'required|array|min:1|max:100',
            'pings.*.session_id'    => 'required|integer',
            'pings.*.latitude'      => 'required|numeric|between:-90,90',
            'pings.*.longitude'     => 'required|numeric|between:-180,180',
            'pings.*.accuracy_m'    => 'nullable|numeric|min:0|max:10000',
            'pings.*.address'       => 'nullable|string|max:500',
            'pings.*.battery_pct'   => 'nullable|integer|between:0,100',
            'pings.*.captured_at'   => 'required|date',
        ];
    }
}
```

---

## 6. Controllers

### 6.1 Helper: `app/Support/Geo.php`

```php
namespace App\Support;

class Geo
{
    /** Great-circle distance in meters. */
    public static function haversine(float $lat1, float $lng1, float $lat2, float $lng2): float
    {
        $earth = 6_371_000.0;
        $dLat  = deg2rad($lat2 - $lat1);
        $dLng  = deg2rad($lng2 - $lng1);
        $a = sin($dLat / 2) ** 2
           + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * sin($dLng / 2) ** 2;
        return 2 * $earth * atan2(sqrt($a), sqrt(1 - $a));
    }
}
```

### 6.2 `app/Http/Controllers/Api/GeofenceController.php`

```php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class GeofenceController extends Controller
{
    public function me(Request $request): JsonResponse
    {
        $employee = $request->user();
        $branch   = $employee->branch; // assumes relation exists

        if (!$branch) {
            return response()->json([
                'status'  => false,
                'message' => 'No branch assigned to this employee.',
            ], 404);
        }

        return response()->json([
            'status' => true,
            'data'   => [
                'branch_id'   => $branch->id,
                'branch_name' => $branch->branch_name,
                'latitude'    => $branch->latitude,
                'longitude'   => $branch->longitude,
                'radius_m'    => $branch->geofence_radius_m,
            ],
        ]);
    }
}
```

### 6.3 `app/Http/Controllers/Api/AttendancePunchController.php`

```php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\Attendance\PunchInRequest;
use App\Http\Requests\Attendance\PunchOutRequest;
use App\Models\AttendancePunch;
use App\Models\AttendanceSession;
use App\Support\Geo;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;

class AttendancePunchController extends Controller
{
    public function punchIn(PunchInRequest $request): JsonResponse
    {
        $employee = $request->user();
        $branch   = $employee->branch;

        if (!$branch) {
            return response()->json([
                'status'  => false,
                'message' => 'No branch assigned.',
            ], 422);
        }

        // Block if an active session already exists.
        $existing = AttendanceSession::where('employee_id', $employee->id)
            ->where('status', 'active')
            ->first();
        if ($existing) {
            return response()->json([
                'status'     => false,
                'error_code' => 'SESSION_ALREADY_OPEN',
                'message'    => 'You already have an open session.',
                'data'       => [
                    'session_id' => $existing->id,
                    'started_at' => $existing->started_at,
                ],
            ], 409);
        }

        [$inside, $distance] = $this->resolveGeofence($branch, $request);

        // Store selfie
        $selfiePath = $this->storeSelfie($request, $employee->id);

        $now = now();

        // Transaction: create punch + session together
        $result = DB::transaction(function () use ($request, $employee, $branch, $selfiePath, $inside, $distance, $now) {
            // Is this the first punch today?
            $isFirstOfDay = !AttendancePunch::where('employee_id', $employee->id)
                ->whereDate('punched_at', $now->toDateString())
                ->exists();

            $session = AttendanceSession::create([
                'employee_id' => $employee->id,
                'branch_id'   => $branch->id,
                'date'        => $now->toDateString(),
                'started_at'  => $now,
                'status'      => 'active',
            ]);

            $punch = AttendancePunch::create([
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
        $session  = AttendanceSession::find($request->input('session_id'));

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
            AttendancePunch::where('employee_id', $employee->id)
                ->whereDate('punched_at', $now->toDateString())
                ->where('type', 'out')
                ->update(['is_last_of_day' => false]);

            $punch = AttendancePunch::create([
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
            return [true, null]; // No fence configured → always "inside"
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
        // storeAs returns the path relative to the disk root.
        return $request->file('selfie')->storeAs($dir, $filename, 'public');
    }
}
```

### 6.4 `app/Http/Controllers/Api/AttendanceLocationPingController.php`

```php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\Attendance\LocationPingBatchRequest;
use App\Http\Requests\Attendance\LocationPingRequest;
use App\Models\AttendanceLocationPing;
use App\Models\AttendanceSession;
use App\Support\Geo;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;

class AttendanceLocationPingController extends Controller
{
    public function store(LocationPingRequest $request): JsonResponse
    {
        $employee = $request->user();
        $session  = AttendanceSession::with('branch')->find($request->input('session_id'));

        if (!$session || $session->employee_id !== $employee->id) {
            return response()->json(['status' => false, 'message' => 'Session not found.'], 404);
        }
        if ($session->status !== 'active') {
            return response()->json(['status' => false, 'message' => 'Session is not active.'], 409);
        }

        [$inside, $distance] = $this->resolveGeofence($session->branch, $request);

        $ping = DB::transaction(function () use ($request, $session, $employee, $inside, $distance) {
            $ping = AttendanceLocationPing::create([
                'session_id'      => $session->id,
                'employee_id'     => $employee->id,
                'latitude'        => $request->input('latitude'),
                'longitude'       => $request->input('longitude'),
                'accuracy_m'      => $request->input('accuracy_m'),
                'address'         => $request->input('address'),
                'inside_geofence' => $inside,
                'distance_m'      => $distance,
                'battery_pct'     => $request->input('battery_pct'),
                'captured_at'     => $request->input('captured_at'),
                'received_at'     => now(),
                'is_queued'       => false,
            ]);
            $session->increment('ping_count');
            return $ping;
        });

        return response()->json([
            'status' => true,
            'data'   => ['ping_id' => $ping->id],
        ]);
    }

    public function batch(LocationPingBatchRequest $request): JsonResponse
    {
        $employee = $request->user();
        $pings    = $request->input('pings');

        // Pre-load sessions for the unique IDs in the batch
        $sessionIds = collect($pings)->pluck('session_id')->unique()->values();
        $sessions   = AttendanceSession::with('branch')
            ->whereIn('id', $sessionIds)
            ->where('employee_id', $employee->id)
            ->where('status', 'active')
            ->get()
            ->keyBy('id');

        $accepted = [];
        $rejected = [];
        $pingIds  = [];

        DB::transaction(function () use ($pings, $sessions, $employee, &$accepted, &$rejected, &$pingIds) {
            foreach ($pings as $idx => $p) {
                $session = $sessions->get($p['session_id']);
                if (!$session) {
                    $rejected[] = ['index' => $idx, 'reason' => 'SESSION_NOT_ACTIVE'];
                    continue;
                }

                [$inside, $distance] = $this->resolveGeofence($session->branch, (object) $p);

                $ping = AttendanceLocationPing::create([
                    'session_id'      => $session->id,
                    'employee_id'     => $employee->id,
                    'latitude'        => $p['latitude'],
                    'longitude'       => $p['longitude'],
                    'accuracy_m'      => $p['accuracy_m'] ?? null,
                    'address'         => $p['address'] ?? null,
                    'inside_geofence' => $inside,
                    'distance_m'      => $distance,
                    'battery_pct'     => $p['battery_pct'] ?? null,
                    'captured_at'     => $p['captured_at'],
                    'received_at'     => now(),
                    'is_queued'       => true,
                ]);

                $accepted[] = $idx;
                $pingIds[]  = $ping->id;
                $session->increment('ping_count');
            }
        });

        return response()->json([
            'status' => true,
            'data'   => [
                'accepted'  => count($accepted),
                'rejected'  => $rejected,
                'ping_ids'  => $pingIds,
            ],
        ]);
    }

    private function resolveGeofence($branch, $request): array
    {
        // Accept either a FormRequest or a plain object from the batch loop.
        $lat = is_object($request) && method_exists($request, 'input')
            ? $request->input('latitude')
            : $request->latitude;
        $lng = is_object($request) && method_exists($request, 'input')
            ? $request->input('longitude')
            : $request->longitude;

        if (!$branch || !$branch->hasGeofence()) {
            return [true, null];
        }
        $distance = (int) round(Geo::haversine(
            (float) $branch->latitude,
            (float) $branch->longitude,
            (float) $lat,
            (float) $lng,
        ));
        return [$distance <= (int) $branch->geofence_radius_m, $distance];
    }
}
```

### 6.5 `app/Http/Controllers/Api/AttendanceViewController.php`

```php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AttendanceLocationPing;
use App\Models\AttendancePunch;
use App\Models\AttendanceSession;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class AttendanceViewController extends Controller
{
    public function today(Request $request): JsonResponse
    {
        $employee = $request->user();
        $today    = now()->toDateString();

        $active = AttendanceSession::where('employee_id', $employee->id)
            ->where('status', 'active')
            ->first();

        $lastPing = null;
        if ($active) {
            $p = AttendanceLocationPing::where('session_id', $active->id)
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

        $punches = AttendancePunch::where('employee_id', $employee->id)
            ->whereDate('punched_at', $today)
            ->orderBy('punched_at')
            ->get()
            ->map(fn ($p) => [
                'type'       => $p->type,
                'punched_at' => $p->punched_at->toIso8601String(),
                'selfie_url' => $p->selfie_url,
                'inside_geofence' => $p->inside_geofence,
                'distance_m' => $p->distance_m,
            ]);

        $sessionsToday = AttendanceSession::where('employee_id', $employee->id)
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
        // Authorization handled via route middleware (role:admin).
        $query = AttendanceSession::with(['employee:id,name,emp_code', 'branch:id,branch_name'])
            ->where('status', 'active');

        if ($request->filled('branch_id')) {
            $query->where('branch_id', $request->integer('branch_id'));
        }

        $sessions = $query->limit($request->integer('limit', 100))->get();

        $data = $sessions->map(function ($s) {
            $lastPing = AttendanceLocationPing::where('session_id', $s->id)
                ->latest('captured_at')
                ->first();

            return [
                'session_id' => $s->id,
                'employee'   => $s->employee,
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

    public function timeline(Request $request, int $sessionId): JsonResponse
    {
        $session = AttendanceSession::with(['punchIn', 'punchOut', 'pings' => fn ($q) => $q->orderBy('captured_at')])
            ->findOrFail($sessionId);

        // Allow self or admin
        $user = $request->user();
        $isAdmin = method_exists($user, 'hasRole') ? $user->hasRole('admin') : false;
        if ($session->employee_id !== $user->id && !$isAdmin) {
            return response()->json(['status' => false, 'message' => 'Forbidden.'], 403);
        }

        return response()->json([
            'status' => true,
            'data'   => [
                'session'   => [
                    'id'         => $session->id,
                    'employee_id'=> $session->employee_id,
                    'started_at' => $session->started_at->toIso8601String(),
                    'ended_at'   => $session->ended_at?->toIso8601String(),
                    'status'     => $session->status,
                ],
                'punch_in'  => $session->punchIn ? [
                    'latitude'   => $session->punchIn->latitude,
                    'longitude'  => $session->punchIn->longitude,
                    'punched_at' => $session->punchIn->punched_at->toIso8601String(),
                    'selfie_url' => $session->punchIn->selfie_url,
                    'inside_geofence' => $session->punchIn->inside_geofence,
                ] : null,
                'punch_out' => $session->punchOut ? [
                    'latitude'   => $session->punchOut->latitude,
                    'longitude'  => $session->punchOut->longitude,
                    'punched_at' => $session->punchOut->punched_at->toIso8601String(),
                    'selfie_url' => $session->punchOut->selfie_url,
                    'inside_geofence' => $session->punchOut->inside_geofence,
                ] : null,
                'pings'     => $session->pings->map(fn ($p) => [
                    'latitude'        => $p->latitude,
                    'longitude'       => $p->longitude,
                    'captured_at'     => $p->captured_at->toIso8601String(),
                    'inside_geofence' => $p->inside_geofence,
                    'accuracy_m'      => $p->accuracy_m,
                ]),
            ],
        ]);
    }
}
```

---

## 7. Policies & authorization

Simplest approach — a route middleware for admin-only endpoints.

### 7.1 `app/Http/Middleware/EnsureIsAdmin.php`

```php
namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsureIsAdmin
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();
        // Adjust to your role system (Spatie, enum, boolean, etc.)
        $isAdmin = $user && (
            (method_exists($user, 'hasRole') && $user->hasRole('admin'))
            || ($user->role ?? null) === 'admin'
        );

        if (!$isAdmin) {
            return response()->json([
                'status'  => false,
                'message' => 'Admin access required.',
            ], 403);
        }

        return $next($request);
    }
}
```

Register in `app/Http/Kernel.php` (Laravel 10) or `bootstrap/app.php` (Laravel 11):

```php
// Laravel 10
protected $middlewareAliases = [
    // ...
    'admin' => \App\Http\Middleware\EnsureIsAdmin::class,
];
```

Laravel 11:
```php
->withMiddleware(function (Middleware $middleware) {
    $middleware->alias(['admin' => \App\Http\Middleware\EnsureIsAdmin::class]);
})
```

---

## 8. Routes

`routes/api.php`:

```php
use App\Http\Controllers\Api\AttendanceLocationPingController;
use App\Http\Controllers\Api\AttendancePunchController;
use App\Http\Controllers\Api\AttendanceViewController;
use App\Http\Controllers\Api\GeofenceController;
use Illuminate\Support\Facades\Route;

Route::middleware('auth:sanctum')->group(function () {

    // Geofence bootstrap
    Route::get('/me/geofence', [GeofenceController::class, 'me']);

    // Punches (multipart) — strict throttle to prevent button-spam
    Route::middleware('throttle:6,1')->group(function () {
        Route::post('/attendance/punch-in',  [AttendancePunchController::class, 'punchIn']);
        Route::post('/attendance/punch-out', [AttendancePunchController::class, 'punchOut']);
    });

    // Location pings (json)
    Route::middleware('throttle:30,1')->group(function () {
        Route::post('/attendance/location-ping',       [AttendanceLocationPingController::class, 'store']);
        Route::post('/attendance/location-ping/batch', [AttendanceLocationPingController::class, 'batch']);
    });

    // Self-views
    Route::get('/attendance/today',                   [AttendanceViewController::class, 'today']);
    Route::get('/attendance/session/{id}/timeline',   [AttendanceViewController::class, 'timeline']);

    // Admin-only
    Route::middleware('admin')->group(function () {
        Route::get('/attendance/live', [AttendanceViewController::class, 'live']);
    });
});
```

---

## 9. Storage & selfie handling

**One-time setup**:
```bash
php artisan storage:link
```
This creates `public/storage` → `storage/app/public`, so files under `storage/app/public/attendance/...` become accessible at `https://hrms.mecpl.in/storage/attendance/...`.

**Path convention** used by the controllers:
```
storage/app/public/attendance/{YYYY}/{MM}/{employee_id}_{unix_timestamp}.jpg
```

**Disk config** (`config/filesystems.php`): default `public` disk is fine. No additional configuration.

**URL building** lives in `AttendancePunch::getSelfieUrlAttribute` — it appends `selfie_path` to `asset('storage/')`, which respects `APP_URL`.

**Cleanup**: selfies are **not** auto-purged even when pings are. HR may need them for audit years later. If you want to add a cap, implement it separately.

---

## 10. Console command — 180-day ping purge

### 10.1 `app/Console/Commands/PurgeOldLocationPings.php`

```php
namespace App\Console\Commands;

use App\Models\AttendanceLocationPing;
use Illuminate\Console\Command;

class PurgeOldLocationPings extends Command
{
    protected $signature = 'attendance:purge-pings {--days=180 : Retention window in days}';
    protected $description = 'Delete attendance location pings older than the retention window.';

    public function handle(): int
    {
        $days   = (int) $this->option('days');
        $cutoff = now()->subDays($days);

        $count = AttendanceLocationPing::where('captured_at', '<', $cutoff)->delete();

        $this->info("Deleted {$count} pings older than {$days} days (before {$cutoff->toDateTimeString()}).");
        return self::SUCCESS;
    }
}
```

### 10.2 Schedule it

**Laravel 10** — `app/Console/Kernel.php`:
```php
protected function schedule(Schedule $schedule): void
{
    $schedule->command('attendance:purge-pings')->dailyAt('02:30');
}
```

**Laravel 11** — `routes/console.php`:
```php
use Illuminate\Support\Facades\Schedule;

Schedule::command('attendance:purge-pings')->dailyAt('02:30');
```

### 10.3 Cron entry on the server

```
* * * * * cd /var/www/hrms && php artisan schedule:run >> /dev/null 2>&1
```

---

## 11. Rate limiting

Already applied in routes:

| Route | Throttle | Reason |
|---|---|---|
| `/attendance/punch-*` | `6,1` (6 req/min) | prevent tap-spam |
| `/attendance/location-ping` | `30,1` | normal cadence is 1 per 30 min; 30/min is generous |
| `/attendance/location-ping/batch` | `30,1` | same bucket |
| everything else (GET) | Laravel default (`60,1`) | standard |

Per-user rate limits are the Sanctum default (keyed by the token user).

---

## 12. Example requests (curl)

All examples assume `TOKEN=<sanctum-token>` and base URL `https://hrms.mecpl.in`.

### 12.1 Fetch the assigned geofence
```bash
curl -H "Authorization: Bearer $TOKEN" \
     -H "Accept: application/json" \
     https://hrms.mecpl.in/api/me/geofence
```

### 12.2 Punch in (multipart)
```bash
curl -X POST "https://hrms.mecpl.in/api/attendance/punch-in" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/json" \
  -F "selfie=@/path/to/selfie.jpg" \
  -F "latitude=18.5743404" \
  -F "longitude=73.7736299" \
  -F "accuracy_m=8.2" \
  -F "address=Pune HQ, Hinjewadi" \
  -F "client_captured_at=2026-04-20T09:05:23+05:30" \
  -F 'device_info={"platform":"android","model":"Pixel 7","os_version":"14","app_version":"1.2.0","battery_pct":73}'
```

### 12.3 Punch out
```bash
curl -X POST "https://hrms.mecpl.in/api/attendance/punch-out" \
  -H "Authorization: Bearer $TOKEN" \
  -F "session_id=3401" \
  -F "selfie=@/path/to/selfie_out.jpg" \
  -F "latitude=18.5743404" \
  -F "longitude=73.7736299" \
  -F "client_captured_at=2026-04-20T17:01:10+05:30"
```

### 12.4 Single location ping
```bash
curl -X POST "https://hrms.mecpl.in/api/attendance/location-ping" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": 3401,
    "latitude": 18.5743,
    "longitude": 73.7736,
    "accuracy_m": 8.2,
    "battery_pct": 73,
    "captured_at": "2026-04-20T09:35:00+05:30"
  }'
```

### 12.5 Batch flush
```bash
curl -X POST "https://hrms.mecpl.in/api/attendance/location-ping/batch" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "pings": [
      {"session_id":3401,"latitude":18.5,"longitude":73.7,"captured_at":"2026-04-20T10:05:00+05:30"},
      {"session_id":3401,"latitude":18.5,"longitude":73.7,"captured_at":"2026-04-20T10:35:00+05:30"}
    ]
  }'
```

### 12.6 Today's attendance (self)
```bash
curl -H "Authorization: Bearer $TOKEN" \
     https://hrms.mecpl.in/api/attendance/today
```

### 12.7 Live attendance (admin)
```bash
curl -H "Authorization: Bearer $ADMIN_TOKEN" \
     "https://hrms.mecpl.in/api/attendance/live?branch_id=12"
```

### 12.8 Session timeline
```bash
curl -H "Authorization: Bearer $TOKEN" \
     https://hrms.mecpl.in/api/attendance/session/3401/timeline
```

---

## 13. Testing checklist

Smoke-test everything from top to bottom before handing off to mobile.

**Migrations**
- [ ] `php artisan migrate:fresh` runs cleanly
- [ ] All four tables exist with expected columns and indexes
- [ ] FKs `session_id`, `punch_in_id`, `punch_out_id` enforce correctly

**Geofence bootstrap**
- [ ] `GET /me/geofence` returns branch lat/lng/radius
- [ ] Employee without a branch → 404
- [ ] Branch without geofence configured → `radius_m: null`

**Punch in**
- [ ] Inside fence → 200, row created with `inside_geofence=1`, selfie saved under correct path, session `active`
- [ ] Outside fence → 200, `inside_geofence=0`, `distance_m` populated (NOT rejected)
- [ ] Second punch-in while session open → 409 with existing `session_id`
- [ ] `is_first_of_day=true` on the first punch-in each day

**Punch out**
- [ ] Valid `session_id` + ownership → 200, session `closed`, `duration_seconds` correct
- [ ] Someone else's `session_id` → 404
- [ ] Already-closed session → 409
- [ ] Outside fence → 200, session still closes
- [ ] `is_last_of_day=true` flips to the newest out-punch

**Location pings**
- [ ] Single ping on active session → 200, `ping_count` incremented
- [ ] Ping on closed session → 409
- [ ] Batch of 10 pings → 200, `accepted=10`, 10 new rows with `is_queued=true`
- [ ] Batch with 1 bad `session_id` → rest accepted, bad one in `rejected[]`

**Views**
- [ ] `/attendance/today` returns active session + all day's punches + total seconds
- [ ] `/attendance/live` as admin → 200 with list
- [ ] `/attendance/live` as employee → 403
- [ ] `/attendance/session/{id}/timeline` as owner → 200
- [ ] Timeline for another employee's session, as non-admin → 403

**Purge**
- [ ] Insert a ping with `captured_at` 200 days ago → `php artisan attendance:purge-pings` deletes it
- [ ] Recent ping (today) stays
- [ ] `attendance_punches` and `attendance_sessions` rows unchanged

**Rate limits**
- [ ] 7 punch-ins in 60 s → 7th returns 429
- [ ] 31 pings in 60 s → 31st returns 429

**Auth**
- [ ] All endpoints without Bearer token → 401

**Selfies**
- [ ] Uploaded file appears at `storage/app/public/attendance/2026/04/{employee_id}_{ts}.jpg`
- [ ] `asset('storage/...')` URL returns the image in a browser
- [ ] `selfie` not JPG/PNG → 422
- [ ] `selfie` > 2 MB → 422

---

## 14. Deployment notes

1. Run `php artisan migrate` (or `migrate:fresh` in staging if safe).
2. Run `php artisan storage:link` on the production host.
3. Ensure `APP_URL` matches the public host so `asset()` generates correct selfie URLs.
4. Add a cron entry for `php artisan schedule:run` (see §10.3).
5. Confirm `storage/app/public/attendance` is writable by the web user (`chown -R www-data:www-data storage`).
6. Seed at least one branch with real `latitude`, `longitude`, `geofence_radius_m`:
   ```sql
   UPDATE branches SET latitude = 18.5743404, longitude = 73.7736299, geofence_radius_m = 50 WHERE id = 12;
   ```
7. Issue a Sanctum token to an existing employee for smoke tests:
   ```php
   $employee = \App\Models\Employee::find(2914);
   $token = $employee->createToken('mobile')->plainTextToken;
   echo $token;
   ```
8. Point the mobile app at `/api/*` and run through the flow.

---

## 15. Column quick-reference (for migrations and queries)

### branches (added columns)

| Column | Type | Null |
|---|---|---|
| latitude | DECIMAL(10,7) | YES |
| longitude | DECIMAL(10,7) | YES |
| geofence_radius_m | SMALLINT UNSIGNED | YES |

### attendance_sessions

| Column | Type | Null |
|---|---|---|
| id | BIGINT UNSIGNED PK | NO |
| employee_id | BIGINT UNSIGNED FK | NO |
| branch_id | BIGINT UNSIGNED FK | NO |
| date | DATE | NO |
| punch_in_id | BIGINT UNSIGNED FK | YES |
| punch_out_id | BIGINT UNSIGNED FK | YES |
| started_at | TIMESTAMP | NO |
| ended_at | TIMESTAMP | YES |
| duration_seconds | INT UNSIGNED | YES |
| ping_count | INT UNSIGNED | NO (default 0) |
| status | ENUM('active','closed','force_closed') | NO (default 'active') |
| created_at / updated_at | TIMESTAMP | NO |

### attendance_punches

| Column | Type | Null |
|---|---|---|
| id | BIGINT UNSIGNED PK | NO |
| employee_id | BIGINT UNSIGNED FK | NO |
| branch_id | BIGINT UNSIGNED FK | NO |
| session_id | BIGINT UNSIGNED FK | NO |
| type | ENUM('in','out') | NO |
| punched_at | TIMESTAMP | NO |
| client_captured_at | TIMESTAMP | YES |
| latitude | DECIMAL(10,7) | NO |
| longitude | DECIMAL(10,7) | NO |
| accuracy_m | FLOAT | YES |
| address | VARCHAR(500) | YES |
| inside_geofence | TINYINT(1) | NO |
| distance_m | INT UNSIGNED | YES |
| selfie_path | VARCHAR(255) | NO |
| device_info | JSON | YES |
| is_first_of_day | TINYINT(1) | NO (default 0) |
| is_last_of_day | TINYINT(1) | NO (default 0) |
| created_at / updated_at | TIMESTAMP | NO |

### attendance_location_pings

| Column | Type | Null |
|---|---|---|
| id | BIGINT UNSIGNED PK | NO |
| session_id | BIGINT UNSIGNED FK (cascade) | NO |
| employee_id | BIGINT UNSIGNED FK | NO |
| latitude | DECIMAL(10,7) | NO |
| longitude | DECIMAL(10,7) | NO |
| accuracy_m | FLOAT | YES |
| address | VARCHAR(500) | YES |
| inside_geofence | TINYINT(1) | NO |
| distance_m | INT UNSIGNED | YES |
| battery_pct | TINYINT UNSIGNED | YES |
| captured_at | TIMESTAMP | NO |
| received_at | TIMESTAMP | NO |
| is_queued | TINYINT(1) | NO (default 0) |
| created_at | TIMESTAMP | NO |

---

## 16. Change log

| Date | Change |
|---|---|
| 2026-04-20 | Initial Laravel implementation guide. Out-of-fence punches are accepted and flagged (not rejected). |
