package supportcrate.helper;

import rust.Ref;
import rust.Result;
import rust.Vec;

/** Mechanical byte-vector operations needed by the Haxe protocol codec. */
@:native("crate::support_crate_admission_fs::AdmissionByteTools")
@:rustCargo({name: "rustix", version: "=1.1.4", defaultFeatures: false, features: ["std", "fs"]})
@:rustExtraSrc("support_crate_admission_fs.rs")
extern class AdmissionByteTools {
	public static function length(bytes:Ref<Vec<Int>>):Int;
	public static function get(bytes:Ref<Vec<Int>>, index:Int):Int;
	public static function append(target:Vec<Int>, source:Vec<Int>):Vec<Int>;

	@:native("append_byte")
	public static function appendByte(target:Vec<Int>, value:Int):Vec<Int>;
	public static function equal(left:Ref<Vec<Int>>, right:Ref<Vec<Int>>):Bool;

	@:native("decode_utf8")
	public static function decodeUtf8(bytes:Vec<Int>):Result<String, AdmissionFsError>;

	@:native("encode_utf8")
	public static function encodeUtf8(value:String):Vec<Int>;

	@:native("compare_utf8")
	public static function compareUtf8(left:String, right:String):Int;

	@:native("utf8_length")
	public static function utf8Length(value:String):Int;
}
