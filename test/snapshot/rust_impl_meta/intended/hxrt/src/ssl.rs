//! `hxrt::ssl`
//!
//! Runtime support for `sys.ssl.*` on the Rust target.
//!
//! Why
//! - The upstream Haxe stdlib declares `sys.ssl.*` as `extern` for sys targets.
//! - `sys.ssl.Socket` is required for HTTPS and TLS-capable networking.
//! - `sys.ssl.Certificate`, `sys.ssl.Key`, and `sys.ssl.Digest` are part of the public std surface.
//!
//! What
//! - Certificate chains (`Certificate`) backed by DER-encoded X.509 certificates.
//! - RSA keys (`Key`) loaded from PEM/DER (subset of the upstream API for now).
//! - Digest helpers (`digest_make`), plus best-effort RSA PKCS#1 v1.5 sign/verify.
//!
//! How
//! - Haxe wrappers in `std/sys/ssl/*` store opaque handles as `HxRef<...>` (Rc<RefCell<...>>).
//! - Haxe calls into these helpers via target code injection (`untyped __rust__`).
//! - Certificate field extraction uses `x509-parser` and returns best-effort data.

use crate::bytes::Bytes;
use crate::cell::{HxCell, HxRc, HxRef};
use crate::exception;
use md5::Md5;
use oid_registry::{
    OID_PKCS9_EMAIL_ADDRESS, OID_X509_COMMON_NAME, OID_X509_COUNTRY_NAME, OID_X509_LOCALITY_NAME,
    OID_X509_ORGANIZATIONAL_UNIT, OID_X509_ORGANIZATION_NAME, OID_X509_STATE_OR_PROVINCE_NAME,
};
use ripemd::Ripemd160;
use rsa::pkcs1::{DecodeRsaPrivateKey, DecodeRsaPublicKey};
use rsa::pkcs8::{DecodePrivateKey, DecodePublicKey};
use rsa::signature::SignatureEncoding;
use rsa::{RsaPrivateKey, RsaPublicKey};
use rustls::pki_types::{PrivateKeyDer, PrivatePkcs1KeyDer, PrivatePkcs8KeyDer};
use sha1::Sha1;
use sha2::{Sha224, Sha256, Sha384, Sha512};
use std::fs;
use std::path::Path;
use x509_parser::prelude::*;

fn throw_custom(msg: String) -> ! {
    exception::throw(crate::dynamic::from(crate::io::Error::Custom(
        crate::dynamic::from(msg),
    )));
}

#[derive(Debug, Clone, Default)]
pub struct Certificate {
    /// DER-encoded certificate chain, leaf-first.
    chain_der: Vec<Vec<u8>>,
}

impl Certificate {
    pub fn empty() -> Certificate {
        Certificate { chain_der: vec![] }
    }

    pub fn from_chain_der(chain_der: Vec<Vec<u8>>) -> Certificate {
        Certificate { chain_der }
    }

    pub fn chain_der(&self) -> &[Vec<u8>] {
        self.chain_der.as_slice()
    }

    pub fn add_chain_der(&mut self, mut more: Vec<Vec<u8>>) {
        self.chain_der.append(&mut more);
    }

    fn leaf_x509(&self) -> Option<X509Certificate<'_>> {
        let leaf = self.chain_der.first()?;
        let (_, cert) = X509Certificate::from_der(leaf.as_slice()).ok()?;
        Some(cert)
    }

    pub fn common_name(&self) -> Option<String> {
        let cert = self.leaf_x509()?;
        let out = cert
            .subject()
            .iter_common_name()
            .next()
            .and_then(|cn| cn.as_str().ok().map(|s| s.to_string()));
        out
    }

    pub fn alt_names(&self) -> Vec<String> {
        let Some(cert) = self.leaf_x509() else {
            return vec![];
        };
        let Ok(Some(san)) = cert.subject_alternative_name() else {
            return vec![];
        };
        san.value
            .general_names
            .iter()
            .filter_map(|gn| match gn {
                GeneralName::DNSName(n) => Some(n.to_string()),
                GeneralName::IPAddress(bytes) => Some(format!("{:?}", bytes)),
                _ => None,
            })
            .collect()
    }

    pub fn not_before_ms(&self) -> i64 {
        let Some(cert) = self.leaf_x509() else {
            return 0;
        };
        asn1_time_to_ms(cert.validity().not_before)
    }

    pub fn not_after_ms(&self) -> i64 {
        let Some(cert) = self.leaf_x509() else {
            return 0;
        };
        asn1_time_to_ms(cert.validity().not_after)
    }

    pub fn subject_field(&self, field: &str) -> Option<String> {
        let cert = self.leaf_x509()?;
        x509_name_field(cert.subject(), field)
    }

    pub fn issuer_field(&self, field: &str) -> Option<String> {
        let cert = self.leaf_x509()?;
        x509_name_field(cert.issuer(), field)
    }
}

fn asn1_time_to_ms(t: ASN1Time) -> i64 {
    // `timestamp()` returns seconds since epoch.
    t.timestamp() * 1000
}

fn x509_name_field(name: &X509Name<'_>, field: &str) -> Option<String> {
    // Common aliases used across Haxe targets:
    // - "CN" / "commonName"
    // - "O"  / "organizationName"
    // - "OU" / "organizationalUnitName"
    // - "C"  / "countryName"
    // - "L"  / "localityName"
    // - "ST" / "stateOrProvinceName"
    // - "emailAddress"
    let oid = match field {
        "CN" | "commonName" => OID_X509_COMMON_NAME,
        "O" | "organizationName" => OID_X509_ORGANIZATION_NAME,
        "OU" | "organizationalUnitName" => OID_X509_ORGANIZATIONAL_UNIT,
        "C" | "countryName" => OID_X509_COUNTRY_NAME,
        "L" | "localityName" => OID_X509_LOCALITY_NAME,
        "ST" | "stateOrProvinceName" => OID_X509_STATE_OR_PROVINCE_NAME,
        "emailAddress" => OID_PKCS9_EMAIL_ADDRESS,
        _ => return None,
    };

    name.iter_by_oid(&oid)
        .next()
        .and_then(|attr| attr.as_str().ok().map(|s| s.to_string()))
}

pub fn cert_new() -> HxRef<Certificate> {
    HxRc::new(HxCell::new(Certificate::empty()))
}

pub fn cert_from_chain_der(chain_der: Vec<Vec<u8>>) -> HxRef<Certificate> {
    HxRc::new(HxCell::new(Certificate::from_chain_der(chain_der)))
}

pub fn cert_load_defaults() -> HxRef<Certificate> {
    // Prefer the OS trust store. If unavailable, fall back to a bundled set.
    let mut out = Certificate::empty();
    if let Ok(store) = rustls_native_certs::load_native_certs() {
        for cert in store {
            out.chain_der.push(cert.as_ref().to_vec());
        }
    }
    HxRc::new(HxCell::new(out))
}

fn cert_from_pem_str(pem: &str) -> Vec<Vec<u8>> {
    let mut cursor = std::io::Cursor::new(pem.as_bytes());
    let mut out: Vec<Vec<u8>> = vec![];
    while let Ok(Some(item)) = rustls_pemfile::read_one(&mut cursor) {
        if let rustls_pemfile::Item::X509Certificate(der) = item {
            out.push(der.as_ref().to_vec());
        }
    }
    out
}

pub fn cert_from_string(pem: &str) -> HxRef<Certificate> {
    HxRc::new(HxCell::new(Certificate::from_chain_der(cert_from_pem_str(
        pem,
    ))))
}

pub fn cert_load_file(file: &str) -> HxRef<Certificate> {
    let path = Path::new(file);
    let data = match fs::read(path) {
        Ok(b) => b,
        Err(e) => throw_custom(format!("Certificate.loadFile: {e}")),
    };

    let chain_der = if data.starts_with(b"-----BEGIN") {
        match std::str::from_utf8(&data) {
            Ok(s) => cert_from_pem_str(s),
            Err(_) => vec![],
        }
    } else {
        vec![data]
    };

    HxRc::new(HxCell::new(Certificate::from_chain_der(chain_der)))
}

pub fn cert_load_path(path: &str) -> HxRef<Certificate> {
    let p = Path::new(path);
    if p.is_file() {
        return cert_load_file(path);
    }

    let mut out = Certificate::empty();
    let entries = match fs::read_dir(p) {
        Ok(e) => e,
        Err(e) => throw_custom(format!("Certificate.loadPath: {e}")),
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_file() {
            if let Some(s) = path.to_str() {
                let c = cert_load_file(s);
                out.add_chain_der(c.borrow().chain_der.clone());
            }
        }
    }
    HxRc::new(HxCell::new(out))
}

pub fn cert_next(cert: &HxRef<Certificate>) -> Option<HxRef<Certificate>> {
    let c = cert.borrow();
    if c.chain_der.len() <= 1 {
        return None;
    }
    Some(cert_from_chain_der(c.chain_der[1..].to_vec()))
}

pub fn cert_add_pem(cert: &HxRef<Certificate>, pem: &str) {
    let mut c = cert.borrow_mut();
    c.add_chain_der(cert_from_pem_str(pem));
}

pub fn cert_add_der(cert: &HxRef<Certificate>, der: &[u8]) {
    let mut c = cert.borrow_mut();
    c.chain_der.push(der.to_vec());
}

#[derive(Debug)]
enum KeyKind {
    RsaPrivate {
        key: Box<RsaPrivateKey>,
        der_bytes: PrivateKeyBytes,
    },
    RsaPublic(Box<RsaPublicKey>),
    /// Non-RSA private key material (kept for TLS, not for `sys.ssl.Digest.sign`).
    PrivateDer {
        der_bytes: PrivateKeyBytes,
    },
}

#[derive(Debug)]
pub struct Key {
    kind: KeyKind,
}

#[derive(Debug)]
enum PrivateKeyBytes {
    Pkcs1(Vec<u8>),
    Pkcs8(Vec<u8>),
    Sec1(Vec<u8>),
}

impl Key {
    pub fn private_key_der(&self) -> Option<PrivateKeyDer<'static>> {
        match &self.kind {
            KeyKind::RsaPrivate { der_bytes, .. } | KeyKind::PrivateDer { der_bytes } => {
                match der_bytes {
                    PrivateKeyBytes::Pkcs1(b) => {
                        Some(PrivateKeyDer::Pkcs1(PrivatePkcs1KeyDer::from(b.clone())))
                    }
                    PrivateKeyBytes::Pkcs8(b) => {
                        Some(PrivateKeyDer::Pkcs8(PrivatePkcs8KeyDer::from(b.clone())))
                    }
                    PrivateKeyBytes::Sec1(b) => Some(PrivateKeyDer::Sec1(
                        rustls::pki_types::PrivateSec1KeyDer::from(b.clone()),
                    )),
                }
            }
            KeyKind::RsaPublic(_) => None,
        }
    }
}

pub fn key_load_file(file: &str, is_public: bool) -> HxRef<Key> {
    let data = match fs::read(file) {
        Ok(b) => b,
        Err(e) => throw_custom(format!("Key.loadFile: {e}")),
    };
    if data.starts_with(b"-----BEGIN") {
        match std::str::from_utf8(&data) {
            Ok(s) => key_read_pem(s, is_public),
            Err(_) => key_read_der(&data, is_public),
        }
    } else {
        key_read_der(&data, is_public)
    }
}

pub fn key_read_pem(pem: &str, is_public: bool) -> HxRef<Key> {
    if is_public {
        // Try PKCS#8 SubjectPublicKeyInfo first, then PKCS#1.
        let k = RsaPublicKey::from_public_key_pem(pem)
            .or_else(|_| RsaPublicKey::from_pkcs1_pem(pem))
            .unwrap_or_else(|e| throw_custom(format!("Key.readPEM(public): {e}")));
        HxRc::new(HxCell::new(Key {
            kind: KeyKind::RsaPublic(Box::new(k)),
        }))
    } else {
        let mut cursor = std::io::BufReader::new(pem.as_bytes());
        let key_der = rustls_pemfile::private_key(&mut cursor)
            .unwrap_or_else(|e| throw_custom(format!("Key.readPEM(private): {e}")))
            .unwrap_or_else(|| throw_custom("Key.readPEM(private): no key found".to_string()));

        let kind = match key_der {
            PrivateKeyDer::Pkcs8(k8) => {
                let bytes = k8.secret_pkcs8_der().to_vec();
                if let Ok(rsa) = RsaPrivateKey::from_pkcs8_der(bytes.as_slice()) {
                    KeyKind::RsaPrivate {
                        key: Box::new(rsa),
                        der_bytes: PrivateKeyBytes::Pkcs8(bytes),
                    }
                } else {
                    // Could be a non-RSA key (ECDSA/Ed25519/etc). Keep DER so TLS can use it.
                    KeyKind::PrivateDer {
                        der_bytes: PrivateKeyBytes::Pkcs8(bytes),
                    }
                }
            }
            PrivateKeyDer::Pkcs1(k1) => {
                let bytes = k1.secret_pkcs1_der().to_vec();
                let rsa = RsaPrivateKey::from_pkcs1_der(bytes.as_slice())
                    .unwrap_or_else(|e| throw_custom(format!("Key.readPEM(private pkcs1): {e}")));
                KeyKind::RsaPrivate {
                    key: Box::new(rsa),
                    der_bytes: PrivateKeyBytes::Pkcs1(bytes),
                }
            }
            PrivateKeyDer::Sec1(k) => {
                let bytes = k.secret_sec1_der().to_vec();
                KeyKind::PrivateDer {
                    der_bytes: PrivateKeyBytes::Sec1(bytes),
                }
            }
            _ => throw_custom("Key.readPEM(private): unsupported key type".to_string()),
        };

        HxRc::new(HxCell::new(Key { kind }))
    }
}

pub fn key_read_der(der: &[u8], is_public: bool) -> HxRef<Key> {
    if is_public {
        let k = RsaPublicKey::from_public_key_der(der)
            .or_else(|_| RsaPublicKey::from_pkcs1_der(der))
            .unwrap_or_else(|e| throw_custom(format!("Key.readDER(public): {e}")));
        HxRc::new(HxCell::new(Key {
            kind: KeyKind::RsaPublic(Box::new(k)),
        }))
    } else {
        if let Ok(k) = RsaPrivateKey::from_pkcs8_der(der) {
            return HxRc::new(HxCell::new(Key {
                kind: KeyKind::RsaPrivate {
                    key: Box::new(k),
                    der_bytes: PrivateKeyBytes::Pkcs8(der.to_vec()),
                },
            }));
        }

        if let Ok(k) = RsaPrivateKey::from_pkcs1_der(der) {
            return HxRc::new(HxCell::new(Key {
                kind: KeyKind::RsaPrivate {
                    key: Box::new(k),
                    der_bytes: PrivateKeyBytes::Pkcs1(der.to_vec()),
                },
            }));
        }

        // Best-effort: treat it as a non-RSA PKCS#8 private key for TLS.
        HxRc::new(HxCell::new(Key {
            kind: KeyKind::PrivateDer {
                der_bytes: PrivateKeyBytes::Pkcs8(der.to_vec()),
            },
        }))
    }
}

fn digest_make_bytes(data: &[u8], alg: &str) -> Vec<u8> {
    match alg {
        "MD5" => {
            use md5::Digest;
            Md5::digest(data).to_vec()
        }
        "SHA1" => {
            use sha1::Digest;
            Sha1::digest(data).to_vec()
        }
        "SHA224" => {
            use sha2::Digest;
            Sha224::digest(data).to_vec()
        }
        "SHA256" => {
            use sha2::Digest;
            Sha256::digest(data).to_vec()
        }
        "SHA384" => {
            use sha2::Digest;
            Sha384::digest(data).to_vec()
        }
        "SHA512" => {
            use sha2::Digest;
            Sha512::digest(data).to_vec()
        }
        "RIPEMD160" => {
            use ripemd::Digest;
            Ripemd160::digest(data).to_vec()
        }
        _ => throw_custom(format!("DigestAlgorithm not supported: {alg}")),
    }
}

pub fn digest_make(data: &[u8], alg: &str) -> HxRef<Bytes> {
    HxRc::new(HxCell::new(Bytes::from_vec(digest_make_bytes(data, alg))))
}

macro_rules! rsa_sign_pkcs1v15 {
    ($digest:ty, $data:expr, $priv_k:expr) => {{
        use rsa::pkcs1v15::{Signature, SigningKey};
        use rsa::signature::Signer;
        let signing_key = SigningKey::<$digest>::new_unprefixed($priv_k.clone());
        let signature: Signature = signing_key.sign($data);
        signature.to_vec()
    }};
}

macro_rules! rsa_verify_pkcs1v15 {
    ($digest:ty, $data:expr, $sig:expr, $pub_k:expr) => {{
        use rsa::pkcs1v15::{Signature, VerifyingKey};
        use rsa::signature::Verifier;
        let verifying_key = VerifyingKey::<$digest>::new_unprefixed($pub_k.clone());
        match Signature::try_from($sig) {
            Ok(signature) => verifying_key.verify($data, &signature).is_ok(),
            Err(_) => false,
        }
    }};
}

pub fn digest_sign(data: &[u8], priv_key: &HxRef<Key>, alg: &str) -> HxRef<Bytes> {
    let key = priv_key.borrow();
    let KeyKind::RsaPrivate { key: priv_k, .. } = &key.kind else {
        throw_custom("Digest.sign expects a private RSA Key".to_string())
    };

    let sig: Vec<u8> = match alg {
        "SHA1" => rsa_sign_pkcs1v15!(Sha1, data, priv_k.as_ref()),
        "SHA224" => rsa_sign_pkcs1v15!(Sha224, data, priv_k.as_ref()),
        "SHA256" => rsa_sign_pkcs1v15!(Sha256, data, priv_k.as_ref()),
        "SHA384" => rsa_sign_pkcs1v15!(Sha384, data, priv_k.as_ref()),
        "SHA512" => rsa_sign_pkcs1v15!(Sha512, data, priv_k.as_ref()),
        _ => throw_custom(format!(
            "DigestAlgorithm not supported for sign (RSA PKCS#1 v1.5): {alg}"
        )),
    };
    HxRc::new(HxCell::new(Bytes::from_vec(sig)))
}

pub fn digest_verify(data: &[u8], signature: &[u8], pub_key: &HxRef<Key>, alg: &str) -> bool {
    let key = pub_key.borrow();
    let KeyKind::RsaPublic(pub_k) = &key.kind else {
        return false;
    };

    match alg {
        "SHA1" => rsa_verify_pkcs1v15!(Sha1, data, signature, pub_k.as_ref()),
        "SHA224" => rsa_verify_pkcs1v15!(Sha224, data, signature, pub_k.as_ref()),
        "SHA256" => rsa_verify_pkcs1v15!(Sha256, data, signature, pub_k.as_ref()),
        "SHA384" => rsa_verify_pkcs1v15!(Sha384, data, signature, pub_k.as_ref()),
        "SHA512" => rsa_verify_pkcs1v15!(Sha512, data, signature, pub_k.as_ref()),
        _ => false,
    }
}
