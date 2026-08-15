package supportcrateadmission;

#if macro
import haxe.io.Bytes;
import haxe.macro.Context;
import haxe.macro.Compiler;
import haxe.macro.Expr;
import haxe.io.Path;
import reflaxe.rust.SupportCrateAdmissionProtocol;
import reflaxe.rust.SupportCrateAdmissionHelperLocator;
import reflaxe.rust.SupportCrateAdmissionHelperLocator.SupportCrateAdmissionHelperLocatorResult;
import reflaxe.rust.RustCompiler;
import reflaxe.rust.SupportCrateAdmissionProtocol.SupportCrateAdmissionAccepted;
import reflaxe.rust.SupportCrateAdmissionProtocol.SupportCrateAdmissionBundle;
import reflaxe.rust.SupportCrateAdmissionProtocol.SupportCrateAdmissionClasspathBinding;
import reflaxe.rust.SupportCrateAdmissionProtocol.SupportCrateAdmissionDeclaration;
import reflaxe.rust.SupportCrateAdmissionProtocol.SupportCrateAdmissionProtocolError;
import reflaxe.rust.SupportCrateAdmissionProtocol.SupportCrateAdmissionRejected;
import reflaxe.rust.SupportCrateAdmissionProtocol.SupportCrateAdmissionRequest;
import reflaxe.rust.SupportCrateAdmissionProtocol.SupportCrateAdmissionResponse;
import reflaxe.rust.SupportCrateAdmissionProtocol.SupportCrateAdmissionTreeEntry;
import sys.FileSystem;
#end

final class Main {
	#if macro
	public static macro function run():Expr {
		testRequest();
		testAcceptedResponse();
		testRejectedResponse();
		testMalformedFrames();
		testHelperLocator();
		return macro null;
	}

	static function testRequest():Void {
		var classpaths = [
			new SupportCrateAdmissionClasspathBinding(0, ""),
			new SupportCrateAdmissionClasspathBinding(1, "../dependency/src/")
		];
		var sourceRoot = ["native", "helper"];
		var request = new SupportCrateAdmissionRequest([
			classpaths[0],
			classpaths[1]
		], [
			new SupportCrateAdmissionDeclaration(0, sourceRoot)
		]);
		classpaths.pop();
		sourceRoot[1] = "changed";
		var requestBytes = SupportCrateAdmissionProtocol.encodeRequest(request);
		assertEquals(
			"4858525341445131010000003a0000000000000002000100000000000000000001000000120000002e2e2f646570656e64656e63792f7372632f000000000200000006006e6174697665060068656c706572",
			requestBytes.toHex(),
			"request golden bytes"
		);
		var decodedRequest = SupportCrateAdmissionProtocol.decodeRequest(requestBytes);
		assertEquals(2, decodedRequest.classpaths().length, "request classpath count");
		assertEquals("../dependency/src/", decodedRequest.classpaths()[1].path, "relative classpath");
		assertEquals("helper", decodedRequest.declarations()[0].sourceRootSegments()[1], "sourceRoot segment");
		var detachedClasspaths = decodedRequest.classpaths();
		detachedClasspaths.pop();
		assertEquals(2, decodedRequest.classpaths().length, "decoded request array is detached");
	}

	static function testAcceptedResponse():Void {
		var source = Bytes.ofString("pub fn answer() -> u8 { 42 }\n");
		var entries = [
			SupportCrateAdmissionTreeEntry.directory(["src"]),
			SupportCrateAdmissionTreeEntry.file(["src", "lib.rs"], source)
		];
		var response:SupportCrateAdmissionResponse = Accepted(new SupportCrateAdmissionAccepted([
			new SupportCrateAdmissionBundle(0, 1, entries)
		]));
		source.set(0, 88);
		entries.pop();
		var responseBytes = SupportCrateAdmissionProtocol.encodeResponse(response);
		assertEquals(
			"4858525341445231010000004b00000000000100000000000000000001000000020000000000010003007372630000000001000200030073726306006c69622e72731d00000070756220666e20616e737765722829202d3e207538207b203432207d0a",
			responseBytes.toHex(),
			"accepted-response golden bytes"
		);
		var decodedResponse = SupportCrateAdmissionProtocol.decodeResponse(responseBytes, 2, 1);
		switch (decodedResponse) {
			case Accepted(value):
				var bundle = value.bundles()[0];
				assertEquals(1, bundle.selectedClasspathRef, "selected classpath");
				assertEquals(2, bundle.entries().length, "tree entry count");
				var decodedBytes = bundle.entries()[1].fileBytes();
				if (decodedBytes == null)
					fail("decoded file entry has no bytes");
				assertEquals("pub fn answer() -> u8 { 42 }\n", decodedBytes.toString(), "file bytes");
				decodedBytes.set(0, 89);
				assertEquals("pub fn answer() -> u8 { 42 }\n", bundle.entries()[1].fileBytes().toString(), "decoded file bytes are detached");
			case Rejected(_):
				fail("accepted response decoded as rejected");
		}
	}

	static function testRejectedResponse():Void {
		var rejection:SupportCrateAdmissionResponse = Rejected(new SupportCrateAdmissionRejected(SourceAmbiguous, 0, -1, -1));
		var rejectionBytes = SupportCrateAdmissionProtocol.encodeResponse(rejection);
		assertEquals(
			"4858525341445231010000001000000001000000000000000400000000000000ffffffffffffffff",
			rejectionBytes.toHex(),
			"rejected-response golden bytes"
		);
		var decodedRejection = SupportCrateAdmissionProtocol.decodeResponse(rejectionBytes, 2, 1);
		switch (decodedRejection) {
			case Accepted(_): fail("rejected response decoded as accepted");
			case Rejected(value):
				assertEquals(0, value.declarationRef, "rejected declaration ref");
				assertEquals(-1, value.classpathRef, "optional rejected classpath ref");
		}
	}

	static function testMalformedFrames():Void {
		var request = SupportCrateAdmissionProtocol.encodeRequest(new SupportCrateAdmissionRequest([
			new SupportCrateAdmissionClasspathBinding(0, ""),
			new SupportCrateAdmissionClasspathBinding(1, "../dependency/src/")
		], [new SupportCrateAdmissionDeclaration(0, ["native", "helper"])]));
		expectProtocolError("classpath path has too many components", () -> SupportCrateAdmissionProtocol.encodeRequest(
			new SupportCrateAdmissionRequest([
				new SupportCrateAdmissionClasspathBinding(0, [for (index in 0...129) "d" + index].join("/"))
			], [new SupportCrateAdmissionDeclaration(0, ["native", "helper"])])));
		expectProtocolError("classpath component is above the closed byte limit",
			() -> SupportCrateAdmissionProtocol.encodeRequest(new SupportCrateAdmissionRequest([
				new SupportCrateAdmissionClasspathBinding(0, [for (_ in 0...128) "é"].join(""))
			], [new SupportCrateAdmissionDeclaration(0, ["native", "helper"])])));
		expectProtocolError("request magic is invalid", () -> SupportCrateAdmissionProtocol.decodeRequest(withByte(request, 0, 0)));
		expectProtocolError("protocol version is unsupported", () -> SupportCrateAdmissionProtocol.decodeRequest(withU16(request, 8, 2)));
		expectProtocolError("request payload length does not match", () -> SupportCrateAdmissionProtocol.decodeRequest(withU32(request, 12, 0)));
		expectProtocolError("request flags must be zero", () -> SupportCrateAdmissionProtocol.decodeRequest(withU32(request, 16, 1)));
		expectProtocolError("classpath refs must equal", () -> SupportCrateAdmissionProtocol.decodeRequest(withU32(request, 32, 0)));
		expectProtocolError("classpath path is not canonical UTF-8", () -> SupportCrateAdmissionProtocol.decodeRequest(withByte(request, 40, 0xff)));
		expectProtocolError("classpath path contains NUL", () -> SupportCrateAdmissionProtocol.decodeRequest(withByte(request, 40, 0)));
		expectProtocolError("declaration reserved field must be zero", () -> SupportCrateAdmissionProtocol.decodeRequest(withU16(request, 64, 1)));
		expectProtocolError("path segment contains a path separator", () -> SupportCrateAdmissionProtocol.decodeRequest(withByte(request, 68, 47)));
		expectProtocolError("frame is truncated", () -> SupportCrateAdmissionProtocol.decodeRequest(request.sub(0, 2)));

		var accepted:SupportCrateAdmissionResponse = Accepted(new SupportCrateAdmissionAccepted([
			new SupportCrateAdmissionBundle(0, 1, [
				SupportCrateAdmissionTreeEntry.directory(["src"]),
				SupportCrateAdmissionTreeEntry.file(["src", "lib.rs"], Bytes.ofString("pub fn answer() -> u8 { 42 }\n"))
			])
		]));
		var response = SupportCrateAdmissionProtocol.encodeResponse(accepted);
		expectProtocolError("response magic is invalid", () -> SupportCrateAdmissionProtocol.decodeResponse(withByte(response, 0, 0), 2, 1));
		expectProtocolError("response status is unknown", () -> SupportCrateAdmissionProtocol.decodeResponse(withU16(response, 16, 2), 2, 1));
		expectProtocolError("success response must contain every expected bundle", () -> SupportCrateAdmissionProtocol.decodeResponse(withU16(response, 18, 0), 2, 1));
		expectProtocolError("response flags must be zero", () -> SupportCrateAdmissionProtocol.decodeResponse(withU32(response, 20, 1), 2, 1));
		expectProtocolError("bundle declaration refs must equal", () -> SupportCrateAdmissionProtocol.decodeResponse(withU32(response, 24, 1), 2, 1));
		expectProtocolError("selected classpath ref is outside", () -> SupportCrateAdmissionProtocol.decodeResponse(withU32(response, 28, 2), 2, 1));
		expectProtocolError("tree entry count is outside", () -> SupportCrateAdmissionProtocol.decodeResponse(withU16(response, 32, 0), 2, 1));
		expectProtocolError("bundle reserved field must be zero", () -> SupportCrateAdmissionProtocol.decodeResponse(withU16(response, 34, 1), 2, 1));
		expectProtocolError("tree-entry kind is unknown", () -> SupportCrateAdmissionProtocol.decodeResponse(withByte(response, 36, 2), 2, 1));
		expectProtocolError("tree-entry reserved field must be zero", () -> SupportCrateAdmissionProtocol.decodeResponse(withByte(response, 37, 1), 2, 1));
		expectProtocolError("tree path segment count is outside", () -> SupportCrateAdmissionProtocol.decodeResponse(withU16(response, 38, 0), 2, 1));
		expectProtocolError("path segment is not canonical UTF-8", () -> SupportCrateAdmissionProtocol.decodeResponse(withByte(response, 42, 0xff), 2, 1));
		expectProtocolError("directory entry cannot contain file bytes", () -> SupportCrateAdmissionProtocol.decodeResponse(withU32(response, 45, 1), 2, 1));
		expectProtocolError("strict byte order", () -> SupportCrateAdmissionProtocol.decodeResponse(withAscii(response, 55, "aaa"), 2, 1));
		expectProtocolError("tree-entry byte length is outside", () -> SupportCrateAdmissionProtocol.decodeResponse(withU32(response, 66, SupportCrateAdmissionProtocol.MAX_FILE_BYTES + 1), 2, 1));
		expectProtocolError("frame is truncated", () -> SupportCrateAdmissionProtocol.decodeResponse(response.sub(0, 2), 2, 1));

		var rejected = SupportCrateAdmissionProtocol.encodeResponse(Rejected(new SupportCrateAdmissionRejected(SourceAmbiguous, 0, -1, -1)));
		expectProtocolError("admission error code is unknown", () -> SupportCrateAdmissionProtocol.decodeResponse(withU16(rejected, 24, 0), 2, 1));
		expectProtocolError("error reserved field must be zero", () -> SupportCrateAdmissionProtocol.decodeResponse(withU16(rejected, 26, 1), 2, 1));
		expectProtocolError("declaration ref is outside", () -> SupportCrateAdmissionProtocol.decodeResponse(withU32(rejected, 28, 1), 2, 1));
		expectProtocolError("classpath ref is outside", () -> SupportCrateAdmissionProtocol.decodeResponse(withU32(rejected, 32, 2), 2, 1));
		expectProtocolError("component index is outside", () -> SupportCrateAdmissionProtocol.decodeResponse(withU32(rejected, 36, SupportCrateAdmissionProtocol.MAX_CLASSPATH_COMPONENTS), 2, 1));

		expectProtocolError("strict byte order", () -> SupportCrateAdmissionProtocol.encodeResponse(Accepted(new SupportCrateAdmissionAccepted([
			new SupportCrateAdmissionBundle(0, 0, [
				SupportCrateAdmissionTreeEntry.file(["same"], Bytes.ofString("a")),
				SupportCrateAdmissionTreeEntry.file(["same"], Bytes.ofString("b"))
			])
		]))));
	}

	static function testHelperLocator():Void {
		Compiler.addClassPath("shadow");
		var compilerPackageRoot = @:privateAccess RustCompiler.supportCrateAdmissionPackageRoot;
		var expectedRootValue = Context.definedValue("support_crate_expected_root");
		if (expectedRootValue == null)
			fail("support_crate_expected_root is missing");
		var expectedRoot = Path.normalize(FileSystem.fullPath(expectedRootValue));
		var darwin = @:privateAccess SupportCrateAdmissionHelperLocator.locateForHost("Mac", "arm64", compilerPackageRoot);
		switch (darwin) {
			case Unavailable(reason): fail("macOS arm64 helper locator failed with reason `" + Std.string(reason) + "`");
			case Available(value):
				assertEquals(expectedRoot, value.packageRoot, "macOS loaded compiler package root");
				assertEquals(Path.normalize(Path.join([
					expectedRoot,
					"native/support-crate-admission/darwin-arm64/hxrs-support-crate-admission"
				])), value.executablePath, "macOS package-owned helper path");
				assertEquals("dd8d561a82e150610ee36b2fb66390361fe04057a9ee788980f9d8a0b8f0293d", value.expectedSha256,
					"macOS helper digest");
		}

		var unsupported = @:privateAccess SupportCrateAdmissionHelperLocator.locateForHost("Linux", "x86_64", compilerPackageRoot);
		switch (unsupported) {
			case Available(_): fail("unsupported host selected a helper");
			case Unavailable(reason): assertEquals(UnsupportedHost, reason, "unsupported host reason");
		}
	}

	static function assertEquals<T>(expected:T, actual:T, name:String):Void {
		if (expected != actual)
			fail(name + ": expected `" + Std.string(expected) + "`, got `" + Std.string(actual) + "`");
	}

	static function fail(detail:String):Void {
		Context.fatalError(detail, Context.currentPos());
	}

	static function expectProtocolError(expected:String, operation:() -> Void):Void {
		try {
			operation();
		} catch (error:SupportCrateAdmissionProtocolError) {
			if (error.message.indexOf(expected) == -1)
				fail("expected protocol error containing `" + expected + "`, got `" + error.message + "`");
			return;
		}
		fail("expected protocol error containing `" + expected + "`");
	}

	static function withByte(source:Bytes, offset:Int, value:Int):Bytes {
		var bytes = source.sub(0, source.length);
		bytes.set(offset, value);
		return bytes;
	}

	static function withU16(source:Bytes, offset:Int, value:Int):Bytes {
		var bytes = source.sub(0, source.length);
		bytes.set(offset, value & 0xff);
		bytes.set(offset + 1, (value >>> 8) & 0xff);
		return bytes;
	}

	static function withU32(source:Bytes, offset:Int, value:Int):Bytes {
		var bytes = source.sub(0, source.length);
		bytes.set(offset, value & 0xff);
		bytes.set(offset + 1, (value >>> 8) & 0xff);
		bytes.set(offset + 2, (value >>> 16) & 0xff);
		bytes.set(offset + 3, (value >>> 24) & 0xff);
		return bytes;
	}

	static function withAscii(source:Bytes, offset:Int, value:String):Bytes {
		var bytes = source.sub(0, source.length);
		var replacement = Bytes.ofString(value);
		bytes.blit(offset, replacement, 0, replacement.length);
		return bytes;
	}
	#end
}
