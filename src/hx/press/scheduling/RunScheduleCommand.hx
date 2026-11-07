package hx.press.scheduling;

import hx.well.console.AbstractCommand;

/**
    `schedule:run` runs the scheduled jobs that are due, such as scheduled
    publishing and plugin tasks. The JVM application runs them itself; on
    PHP, call it from cron every minute: `php hxwell.boot.php schedule:run`.
**/
class RunScheduleCommand extends AbstractCommand<Int> {
    public override function group():String {
        return "schedule";
    }

    public function signature():String {
        return "run";
    }

    public function description():String {
        return "runs the scheduled jobs that are due";
    }

    public function handle():Int {
        var started = ScheduledJobs.runPending();
        Sys.println('Ran ${started} due scheduled jobs.');
        return started;
    }
}
