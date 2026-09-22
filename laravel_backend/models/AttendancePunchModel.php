<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AttendancePunchModel extends Model
{
    protected $table = 'attendance_punches';

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
        return $this->belongsTo(AttendanceSessionModel::class, 'session_id');
    }

    public function getSelfieUrlAttribute(): ?string
    {
        return $this->selfie_path
            ? asset('storage/' . ltrim($this->selfie_path, '/'))
            : null;
    }
}
