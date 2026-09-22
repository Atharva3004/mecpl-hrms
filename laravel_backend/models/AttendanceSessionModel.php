<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class AttendanceSessionModel extends Model
{
    protected $table = 'attendance_sessions';

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
        return $this->belongsTo(EmployeeModel::class, 'employee_id');
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(BranchModel::class, 'branch_id');
    }

    public function punches(): HasMany
    {
        return $this->hasMany(AttendancePunchModel::class, 'session_id');
    }

    public function pings(): HasMany
    {
        return $this->hasMany(AttendanceLocationPingModel::class, 'session_id');
    }

    public function punchIn(): BelongsTo
    {
        return $this->belongsTo(AttendancePunchModel::class, 'punch_in_id');
    }

    public function punchOut(): BelongsTo
    {
        return $this->belongsTo(AttendancePunchModel::class, 'punch_out_id');
    }
}
