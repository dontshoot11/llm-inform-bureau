import Foundation
import Security

/// How this copy of the app is signed, as the system sees it.
///
/// Asked for one sentence in the panel, and worth its own file because the fact is about the
/// app itself rather than about anything it reads. Signed ad-hoc, the app has no identity
/// beyond the hash of its binary: every build is a different app to the system, and every
/// permission a person gave by hand belongs to the build that asked for it. A copy signed with
/// a certificate keeps those permissions across versions, which is why the two are told apart
/// here instead of assumed — the development Mac signs with one (`Scripts/build-app.sh`), the
/// image handed out does not.
///
/// Read once and kept: a running app cannot change how it was signed.
enum OwnSignature {
    /// Whether this copy carries an ad-hoc signature.
    ///
    /// `false` when the question cannot be answered at all — an unsigned binary, or a system
    /// that refused to say. The sentence this feeds is an extra explanation, and one withheld
    /// costs a person less than one that may be wrong.
    static let isAdHoc: Bool = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return false }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return false
        }
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard
            SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
            let information = information as? [String: Any],
            let signature = information[kSecCodeInfoFlags as String] as? UInt32
        else { return false }
        // `kSecCodeSignatureAdhoc`, by its value: the constant is a macro in `CSCommon.h` that
        // Swift does not import.
        return signature & 0x0002 != 0
    }()
}
