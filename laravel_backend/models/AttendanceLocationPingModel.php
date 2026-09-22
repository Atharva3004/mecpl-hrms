<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AttendanceLocationPingModel extends Model
{
    public $timestamps = false;

    protected $table = 'attendance_location_pings';

    protected $fillable = [
        'session_id', 'employee_id',
        'latitude', 'longitude', 'accuracy_m', 'address',
        'inside_geofence', 'distance_m', 'battery_pct',
        'captured_at', 'received_at', 'is_queued', 'selfie_path',
    ];

    public function getSelfieUrlAttribute(): ?string
    {
        return $this->selfie_path
            ? asset('storage/' . ltrim($this->selfie_path, '/'))
            : null;
    }

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
        return $this->belongsTo(AttendanceSessionModel::class, 'session_id');
    }
}
