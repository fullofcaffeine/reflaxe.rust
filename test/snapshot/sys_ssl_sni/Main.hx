import sys.net.Host;
import sys.ssl.Certificate;
import sys.ssl.Key;
import sys.ssl.Socket;
import sys.thread.Thread;

class Main {
	static function main():Void {
		var mainThread = Thread.current();
		Thread.create(() -> {
			var defaultCertPem = "-----BEGIN CERTIFICATE-----\nMIIDETCCAfmgAwIBAgIUVftG+IyWIEqIQE+K9ztyXCDYIcswDQYJKoZIhvcNAQEL\nBQAwGDEWMBQGA1UEAwwNZGVmYXVsdC5sb2NhbDAeFw0yNjAzMDcwNjA1NTBaFw0y\nNzAzMDcwNjA1NTBaMBgxFjAUBgNVBAMMDWRlZmF1bHQubG9jYWwwggEiMA0GCSqG\nSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCktatoj06k/dqldeSzjPUnPxeMC/WpprMz\n7tHisw82tHc0Xk18wW/m0Dm+W11kLlq+k5fNuVoQTcqaQDkLF0Zy+Q2K+GWLRCux\n7Ms0ixw6oSIUFnaG8+SByKuEfaW232ZKCWFsSxq0PdVKT3jjcc3ivv6j/kOsbE7j\njELMP9w1askakA/I8CWM0AZyYVZ5ajwYcBBQm1UOzWLeoT+UU7O9VKsEIQHCGt5P\np7U/PDqh5z7KJ+XWIG/jpjZ8IYEo8fTxik+16jN34Ubpnx+I/wUmLK4Aqh2VuuZz\nmmcUFD7JLC+r9ymOUa7DS0bWyUoBDzZyvAO1577p7SXi9/IqJ3NpAgMBAAGjUzBR\nMB0GA1UdDgQWBBR7eOzK13X2mO5Kpc9MZOFGJ+MdlDAfBgNVHSMEGDAWgBR7eOzK\n13X2mO5Kpc9MZOFGJ+MdlDAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBCwUA\nA4IBAQAxilSFs9ZEEI5RFGVpWUTCH8Iuewc4K0JH2LbGqExgLu5MQJF5xsGoEBRe\nmDB3duaMDwnoDY19hdoClIz/Z5IO0wPEcny3hTb582W8+cRDiCQx0Qz5g2NpsfGH\nwZaGyVzSS2xbt0F6TPRQarXtzV97J067j7bRuMbD4fFYb6iqF1GbaaQsP89sA9b4\nx8yT0TGREdx2Dw29lokd4H16b3O9aYX274qZk9qpgE3oYpCeNsjHCSdTWRDw2+pg\ncKP2FsxcbB4qChjPXhhE5I3zDMTI1/4r4wGbnVIud6TmibElpAU6hwbpo1onyxKw\nVCpI190WWaS+Cz+9vGVNBSsRYjgN\n-----END CERTIFICATE-----\n";
			var defaultKeyPem = "-----BEGIN PRIVATE KEY-----\nMIIEvwIBADANBgkqhkiG9w0BAQEFAASCBKkwggSlAgEAAoIBAQCktatoj06k/dql\ndeSzjPUnPxeMC/WpprMz7tHisw82tHc0Xk18wW/m0Dm+W11kLlq+k5fNuVoQTcqa\nQDkLF0Zy+Q2K+GWLRCux7Ms0ixw6oSIUFnaG8+SByKuEfaW232ZKCWFsSxq0PdVK\nT3jjcc3ivv6j/kOsbE7jjELMP9w1askakA/I8CWM0AZyYVZ5ajwYcBBQm1UOzWLe\noT+UU7O9VKsEIQHCGt5Pp7U/PDqh5z7KJ+XWIG/jpjZ8IYEo8fTxik+16jN34Ubp\nnx+I/wUmLK4Aqh2VuuZzmmcUFD7JLC+r9ymOUa7DS0bWyUoBDzZyvAO1577p7SXi\n9/IqJ3NpAgMBAAECggEAECDG2jvwGjlOO9XtsUQr7C4iHuE76qMLWJo5vI5GfteQ\ndZUHVuA1Fh+NC+3z2N+uHIukuWz9G+wWGuEPhN3AVPk8oX89qDOiaK90XV6Cwt3s\n0ZU6gW/nz+qHmvdXru60nCrLephnEr+cP0TFZFYMMDf+BK5cz4kid2cQUmItbKBy\nE9k1vHvyyLONK18y72IXsMEA572V+AhtvWVar5qUJiY2+dWtxmWh9dzUvWCUJ/Gj\niqyrJdNxHJfXdteT8QpJEndsX19MWNAMZY+e10XOVzs2Rd4RdnlLwUE37HbPz73V\nC1z2h6tshSOYi9ZwlNdYEjfWbuiQimwgljwc9/NagQKBgQDg4JkcchEOmntEXPz0\n/HTEmAd7Sl75V0ozj7xPTYcaSvdoEtLEbUJbGoVfLKJM17jLuEjpisS1IHa29kkG\n2PACbbIRzOLlCA2Spkzm9R2Rni9qbBCwYbnYbdhV+hshcnr6LwUt8KBAFHBCk2lW\nMfiCsBE1KzBeye1JFxIZ9+dyKQKBgQC7gVSvPDIqPRYP8l8sLbONMHTNhbZpMh23\npdD1i0YpYTIuvrxZMXwY6gt71SJcHIwyh/6HEg8mAIMZutdRzpZc4NWQw98yG9Zo\nkpY7S2uLZ8YnARps+NprdWiARkY3PJjIiK7tieNo+dQtfBeuL3Ox7s/XR0nDUXMP\nxkuAnByfQQKBgQCks9twehsEFyExcOnUhRMA6liQdGgbN1OhcCT78EyDdWS/VQoJ\n0/xFvabxjj9RCK7QhqjgZEKuZpiMaNYTrdAb9zv0zZthJATM5ABvKBgAD1urFnsi\ntHDpk4pfbk9wr+hiVQ32F8dHJ7EREeaUuwTIsyvnRTqoMj0Yy0z2uBtMAQKBgQC2\nEnG+7z7vEP4ZYgrUhVQyp3jkERD9uTJuH892f1UT3VOzXHbcTVbpgmrARkflFbt1\nXeTkF78p8ZlcJLfssiQD8DaxKeHTcICUbrL+xM+bQJuDSGj2o/bEHe/pj1OjU24w\nW7kw45I1X1KPEE6WT3GSuAiOTKTtymtmR/EM44pPgQKBgQC52gWDbpJb1UREu9Sb\naIy1zgqGhSxg1DLChu4vz3t5ZBhWoiw6wG7vQDrtrn9Jl61mVtog0rSTSiIj726W\nLDxSrTdYBhcgkbJf/fw1N6Uk+FfJcVS/zuoJwogkiP6tmircL0qA9sYR4RZo2ubE\nAg6A+vHIw54BclYKSczsXnCe+A==\n-----END PRIVATE KEY-----\n";
			var altCertPem = "-----BEGIN CERTIFICATE-----\nMIIDCTCCAfGgAwIBAgIUJPb0jv8gnhTKZNa3oizqRfCqOEgwDQYJKoZIhvcNAQEL\nBQAwFDESMBAGA1UEAwwJYWx0LmxvY2FsMB4XDTI2MDMwNzA2MDU1MFoXDTI3MDMw\nNzA2MDU1MFowFDESMBAGA1UEAwwJYWx0LmxvY2FsMIIBIjANBgkqhkiG9w0BAQEF\nAAOCAQ8AMIIBCgKCAQEAmqXcaJ2pKONBHCPbOvMz5qXZ6QemxLp06iZivQ7+YzIS\nB5mIIE7TPbNgyLy0Ps5fOcXC/uXdRPv7VzC4Z1v3Fqhei1lwpEyHdvbUVJrB7qyS\ny1BgvjED9IrCwdiLjm3KahI5BubhG51cJ2w4kEEcyr7ab3EBrBnEHH2BhgDES0z+\nMhOoXJtU754nC4iNhGTcvR94r+CqiqMxCIawkwUyLfkhU+MtKX/43QryCTePH42G\nn/RBAVyf2X0pngEfad48RLHx9w9BCxka0n3d4wNGaXB9lmxUGv9L/8vec1C8Ve41\nLn3qCqZBhPYMs4kNWT2sIGhuCJSB9Xo65/RaWEeyaQIDAQABo1MwUTAdBgNVHQ4E\nFgQUfrEeOpv0RyKf+pg7iO7fJS174rAwHwYDVR0jBBgwFoAUfrEeOpv0RyKf+pg7\niO7fJS174rAwDwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEAJ1UI\nRyBAJppSOnwbbnQYQOmJp7ZxNKYRT8KinDQ13P9qrIvUGG9L5tkJSUNbK/Wffo44\nBPMM02p+aQWFU/TzuuGDC3naB8GcLCfDovkUdN2RVk1VN53yGHxZ+oQam5JWtkBA\nNmQa+yq9A0Ww/1mmDgpYO3BTAsK7cxAUbxAX57lOKa0rJi0EXbZrGxVZBvE3IEYV\nLtPUee3vgqpfvJseJKyfli8VWI670ddD/xTdVgSjm4ynknhFWXj+2taKnLEIxBUr\nqUgxdERhaQll9l13GK/dtsl2io9GvCXzI5rzcB8K+DctKY5F8YivvaUusAcXjASa\nnlRJKhRmcc2A8RDsPw==\n-----END CERTIFICATE-----\n";
			var altKeyPem = "-----BEGIN PRIVATE KEY-----\nMIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQCapdxonako40Ec\nI9s68zPmpdnpB6bEunTqJmK9Dv5jMhIHmYggTtM9s2DIvLQ+zl85xcL+5d1E+/tX\nMLhnW/cWqF6LWXCkTId29tRUmsHurJLLUGC+MQP0isLB2IuObcpqEjkG5uEbnVwn\nbDiQQRzKvtpvcQGsGcQcfYGGAMRLTP4yE6hcm1TvnicLiI2EZNy9H3iv4KqKozEI\nhrCTBTIt+SFT4y0pf/jdCvIJN48fjYaf9EEBXJ/ZfSmeAR9p3jxEsfH3D0ELGRrS\nfd3jA0ZpcH2WbFQa/0v/y95zULxV7jUufeoKpkGE9gyziQ1ZPawgaG4IlIH1ejrn\n9FpYR7JpAgMBAAECggEAETrLs9Gl+j7Yfxe9GgQk2wyNGs3+DfLGqhxA+baZD8jx\nMozP2mah2SDaNn80tz8jo6KFi0Plq0UGP5R3ZRedT7ZOQ0kBmGKI4K+XID52Px7V\nw4Zm4uW/3q/Ti0iSotmXWMpDNYJFX//gF6nSYvsIJ8wL9ujQooGj5Hc0ti7xb8Cd\nxJVtdY0lfWM7UwJWEeQPyJKYHwuGCJTY8+oy7aK2C5lDpFYA/MO9RggQukroZfPG\n8MW5Z9sKCYB5QlRNvFnSM1e+jIAgxM09+TAgvi+cm2uyF0+yv8oSMh0Dw6QjEtL4\nLhscR+bYeZKHTPZ2E+T815nB6eTDg4Skg2q8CLETMQKBgQDLB1ZaY/o43jXuyOyp\nApO+p5/9qd55f7tDrClJcSMroVH8nBdeSLNSAQHpPluNfZFJlAwtzhC+5UcRdiiA\n1zHac8OPWbUYxWH6mDDJA94CPRJY41JXACLXbvbVSpCxB7QMrSkDcuFs90xIi9b4\nzkIUL2lnQm7UGexSKN8kaVI0UQKBgQDC/xUB4+een8EnDNMaBg6JqJqQAb098hUx\nl8UWUsHLSTdJeb8qig0j5Nq0qRdZQjp5lfhCDmJBbkZTuwz3lixNuHpxfUUTju0R\n/J31z151IUqFqOJjmvPyTw9I3iT9UDciU9bHPUkzrQd5iZbK9/4xX2T5Qvc9eC/V\n+mR4sioOmQKBgCoRFCBYdMERsaUPNpHyOcCYJLs/VhxgjeGAq3FPItVocH9hrCnZ\n8GW+VbIJPJj9env/U+KtvqR/BxGkJNJFREwaDlwGX1KJmzp8DCeqSHa4RrPqLeZe\n3dk7YaNh9sbnbLPvsP7I79JPDxw89UbKHcDm7fT6O9JwqJmBZHK7689xAoGAduFy\n2kMqy69T383Wya/VnyFWkeMtj52ORDzmIFT150zM0xPRc0rU9gQpPik0netdoRDI\nWOVSC9gCMjwAjNVWT0/f/l7EBUeGywd6+gih6sEQIOq0kss+XITMqb0dSf5kjp4U\nfEWl4kZkHzm94CJPK6Sf98NW3nfumgLczCS6tUkCgYA++BBR+cfVo9944ritaWtt\nhMosCULoLuodKYf9OWKr+YtuxuBLB5GYkmDSmOPE6AXhE0dPOUmqPsFesHrgOBHS\nXv1y3xClj0c/lxPT7eCyI6FKgIrG5zwG5VPo3H4zvDfAJRuMzrKGXWVHn3hgrTGc\nVsJr+neLL50qgTRZcXWuqg==\n-----END PRIVATE KEY-----\n";
			var serverHost = new Host("127.0.0.1");
			try {
				var listener = new Socket();
				listener.bind(serverHost, 0);
				listener.listen(1);
				mainThread.sendMessage(listener.host().port);

				var server = listener.accept();
				server.setCertificate(Certificate.fromString(defaultCertPem), Key.readPEM(defaultKeyPem, false));
				server.addSNICertificate(name -> name == "alt.local", Certificate.fromString(altCertPem), Key.readPEM(altKeyPem, false));
				server.handshake();
				server.output.writeString("server-ok");
				server.close();
				listener.close();
			} catch (e:Dynamic) {
				mainThread.sendMessage("error:" + Std.string(e));
			}
		});

		var host = new Host("127.0.0.1");
		var port:Int = cast Thread.readMessage(true);
		try {
			var client = new Socket();
			client.verifyCert = false;
			client.setHostname("alt.local");
			client.connect(host, port);
			client.handshake();

			Sys.println("peerCN=" + client.peerCertificate().commonName);
			Sys.println("payload=" + client.input.readString("server-ok".length));
			client.close();
		} catch (e:Dynamic) {
			Sys.println("clientError=" + Std.string(e));
		}

		var serverStatus = Thread.readMessageString(false);
		Sys.println("serverStatus=" + (serverStatus == null ? "ok" : serverStatus));
	}
}
