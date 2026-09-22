<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class BranchModel extends Model
{
    use HasFactory;
    protected $table="branches";

    protected $fillable = [
        'branch_name','latitude','longitude','geofence_radius_m',
        'l1','l2','l3','l4','l5','l6','on_site','qa','ehs','store','qs_billing','address','ec_l1','ec_l2','ec_l3','ec_l4','ec_l5','ec_l6'
    ];

    protected $casts = [
        'latitude'          => 'float',
        'longitude'         => 'float',
        'geofence_radius_m' => 'integer',
    ];

    public function hasGeofence(): bool
    {
        return $this->latitude !== null
            && $this->longitude !== null
            && $this->geofence_radius_m > 0;
    }

    

    // Custom relationship to fetch employees from l1 to l6
    public function employeeDetails()
    {
        return EmployeeModel::whereIn('id', [
            $this->l1, $this->l2, $this->l3, $this->l4, $this->l5, $this->l6, $this->on_site, $this->qa, $this->ehs, $this->store, $this->qs_billing, $this->ec_l1, $this->ec_l2, $this->ec_l3, $this->ec_l4, $this->ec_l5, $this->ec_l6
        ])->get();
    }

    
    // Example: Get L1 Employee
    // $l1Employee = $branch->getEmployeeByColumn('l1');
    public function getEmployeeByColumn($columnName)
    {
        if (!in_array($columnName, ['l1', 'l2', 'l3', 'l4', 'l5', 'l6', 'on_site', 'qa', 'ehs', 'store', 'qs_billing','address','ec_l1','ec_l2','ec_l3','ec_l4','ec_l5','ec_l6'])) {
            return null; // Invalid column
        }

        $employeeId = $this->$columnName;

        return $employeeId ? EmployeeModel::find($employeeId) : null;
    }

    public function approvalDetails()
    {
        return $this->hasMany(OnboardingApprovalModel::class, 'br_id', 'id');
    }


}
