<?php

namespace App\Console;

use Illuminate\Console\Scheduling\Schedule;
use Illuminate\Foundation\Console\Kernel as ConsoleKernel;

class Kernel extends ConsoleKernel
{
    /**
     * Define the application's command schedule.
     *
     * @param  \Illuminate\Console\Scheduling\Schedule  $schedule
     * @return void
     */
    // protected function schedule(Schedule $schedule)
    // {
    //     $schedule->command('performance:send-probation-reminder')
    //             ->dailyAt('10:00')
    //             ->timezone('Asia/Kolkata');
        
    //     $schedule->command('performance:send-probation-reminder')
    //             ->dailyAt('14:00')
    //             ->timezone('Asia/Kolkata');

    //     $schedule->command('performance:send-probation-reminder')
    //         ->dailyAt('17:00')
    //         ->timezone('Asia/Kolkata');
    // }
    protected function schedule(Schedule $schedule)
    {
        /**
         * DATE 1 to 3 → 4 reminders
         */
        $schedule->command('performance:send-probation-reminder')
            ->dailyAt('10:00')
            ->timezone('Asia/Kolkata')
            ->when(fn () => now()->day >= 1 && now()->day <= 3);

        $schedule->command('performance:send-probation-reminder')
            ->dailyAt('12:00')
            ->timezone('Asia/Kolkata')
            ->when(fn () => now()->day >= 1 && now()->day <= 3);

        $schedule->command('performance:send-probation-reminder')
            ->dailyAt('14:00')
            ->timezone('Asia/Kolkata')
            ->when(fn () => now()->day >= 1 && now()->day <= 3);

        $schedule->command('performance:send-probation-reminder')
            ->dailyAt('17:00')
            ->timezone('Asia/Kolkata')
            ->when(fn () => now()->day >= 1 && now()->day <= 3);


        /**
         * DATE 4 to 24 → 1 reminder
         */
        $schedule->command('performance:send-probation-reminder')
            ->dailyAt('10:00')
            ->timezone('Asia/Kolkata')
            ->when(fn () => now()->day >= 4 && now()->day <= 24);


        /**
         * DATE 25 to 31 → 3 reminders
         */
        $schedule->command('performance:send-probation-reminder')
            ->dailyAt('10:00')
            ->timezone('Asia/Kolkata')
            ->when(fn () => now()->day >= 25);

        $schedule->command('performance:send-probation-reminder')
            ->dailyAt('14:00')
            ->timezone('Asia/Kolkata')
            ->when(fn () => now()->day >= 25);

        $schedule->command('performance:send-probation-reminder')
            ->dailyAt('17:00')
            ->timezone('Asia/Kolkata')
            ->when(fn () => now()->day >= 25);

        /**
         * Biometric Attendance Sync — runs full day, user sets interval on server
         */
        $schedule->command('attendance:sync')
            ->everyMinute()
            ->timezone('Asia/Kolkata')
            ->withoutOverlapping()
            ->runInBackground();

        /**
         * Process Daily Attendance — runs every 15 minutes for live status updates
         */
        $schedule->command('attendance:process')
            ->everyFifteenMinutes()
            ->timezone('Asia/Kolkata')
            ->withoutOverlapping()
            ->runInBackground();

        /**
         * Generate Monthly Summary — runs every hour to keep aggregated stats updated
         */
        $schedule->command('attendance:monthly-summary')
            ->hourly()
            ->timezone('Asia/Kolkata')
            ->withoutOverlapping()
            ->runInBackground();

        /**
         * Monthly Attendance Re-Sync — runs daily at 06:00 IST
         * Re-syncs entire current month from biometric devices,
         * reprocesses all days, and regenerates monthly summary.
         * Catches data missed due to machine/network downtime.
         */
        $schedule->command('attendance:monthly-resync')
            ->dailyAt('06:00')
            ->timezone('Asia/Kolkata')
            ->withoutOverlapping()
            ->runInBackground();

        /**
         * Leave Accrual Engine — runs daily at 00:05 IST
         * Credits leave balances per policy (Advance / Pro-rata / Year-End)
         * and frequency (Yearly / Monthly / Quarterly / Daily).
         * Also processes carry-forward on the first day of a new leave year.
         */
        $schedule->command('leave:accrue')
            ->dailyAt('00:05')
            ->timezone('Asia/Kolkata')
            ->withoutOverlapping()
            ->runInBackground()
            ->appendOutputTo(storage_path('logs/leave-accrual.log'));

        /**
         * Punch-out reminder — sends FCM push at 19:00 IST
         * to employees punched in for over 9 hours
         */
        $schedule->call(function () {
            $nineHoursAgo = now()->subHours(9);
            \App\Models\AttendanceSessionModel::where('status', 'active')
                ->where('started_at', '<', $nineHoursAgo)
                ->with('employee')
                ->get()
                ->each(function ($session) {
                    if ($session->employee && $session->employee->fcm_token) {
                        app(\App\Services\FcmService::class)->sendToUser(
                            $session->employee,
                            'Punch-out reminder',
                            "You've been punched in for over 9 hours",
                            ['route' => 'tab', 'tab' => 'attendance']
                        );
                    }
                });
        })->dailyAt('19:00')->timezone('Asia/Kolkata');

        /**
         * Purge old location pings — runs daily at 02:30 IST
         * Deletes attendance_location_pings older than 180 days.
         */
        $schedule->command('attendance:purge-pings')
            ->dailyAt('02:30')
            ->timezone('Asia/Kolkata')
            ->withoutOverlapping()
            ->runInBackground();
    }

    /**
     * Register the commands for the application.
     *
     * @return void
     */
    protected function commands()
    {
        $this->load(__DIR__.'/Commands');

        require base_path('routes/console.php');
    }
}
