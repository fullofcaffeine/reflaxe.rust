package supportcrateadmissionrunner;

#if macro
import haxe.io.Bytes;
import haxe.macro.Context;
import haxe.macro.Expr;
import reflaxe.rust.SupportCrateAdmissionRunner;
import reflaxe.rust.SupportCrateAdmissionRunner.SupportCrateAdmissionRunFailure;
import reflaxe.rust.SupportCrateAdmissionHelperLocator.SupportCrateAdmissionHelperLocation;
#end

final class Main {
	#if macro
	public static macro function run():Expr {
		var executable = requiredDefine("support_crate_runner_executable");
		var expected = requiredDefine("support_crate_runner_expected");
		if (expected == "HelperValid" || expected == "HelperInvalid") {
			var digest = requiredDefine("support_crate_runner_sha256");
			var valid = @:privateAccess SupportCrateAdmissionRunner.validHelper(new SupportCrateAdmissionHelperLocation("", executable, digest));
			if (valid != (expected == "HelperValid"))
				Context.fatalError('expected `${expected}`', Context.currentPos());
			return macro null;
		}
		var deadlineValue = requiredDefine("support_crate_runner_deadline_ms");
		var deadline = Std.parseInt(deadlineValue);
		if (deadline == null || deadline < 1)
			Context.fatalError("invalid support_crate_runner_deadline_ms", Context.currentPos());
		var result = @:privateAccess SupportCrateAdmissionRunner.execute(executable, Bytes.ofString("request"), deadline);
		var actual = switch result.failure {
			case null: "Completed";
			case TimedOut: "TimedOut";
			case PipeFailed: "PipeFailed";
			case ExitFailed: "ExitFailed";
			case StderrRejected: "StderrRejected";
			case HelperInvalid | StartFailed | ProtocolRejected: "Unexpected";
		};
		if (actual != expected)
			Context.fatalError('expected `${expected}`, received `${actual}`', Context.currentPos());
		if (actual == "Completed") {
			if (result.stdout.toString() != "x")
				Context.fatalError("completed probe did not retain exact stdout", Context.currentPos());
		} else if (result.stdout.length != 0) {
			Context.fatalError("failed execution retained stdout bytes", Context.currentPos());
		}
		return macro null;
	}

	static function requiredDefine(name:String):String {
		var value = Context.definedValue(name);
		if (value == null || value.length == 0)
			Context.fatalError('missing `${name}`', Context.currentPos());
		return value;
	}
	#end
}
