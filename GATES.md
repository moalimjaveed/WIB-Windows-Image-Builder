# Gates: WIB v0.2.29 Production Remediation

OWNS: lib/**, modules/**, profiles/**, tests/**, tools/**, docs/**, README.md, CHANGELOG.md, WIB-plan.md, GATES.md

Scope: Resolve v0.2.28 forensic audit findings (WIB-046 handle-bound destination replace race closure in Set-WibDurableJsonFile and New-WibUnattend.ps1 with non-throwing AfterFinalValidationBeforeReplace adversary tests; WIB-047 single-buffer immutable staging snapshot under FileShare.None in Get-WibValidatedStageSnapshot and single-handle Assert-WibStagedFileStillMatches; WIB-048 backup cleanup check-then-change race elimination via handle-bound ACL setting in Complete-WibBackupCleanup; WIB-049 hermetic oscdimg Authenticode and strict allowlist enforcement matrix with mock seams; while maintaining WIB-001/WIB-045 physical ISO-to-VM release gate status) and verify 100% pass across all 655 assertions and 22 gates.

- [x] G1: Adaptive profile resolution and Test-WibRecoveryState effectiveHash acceptance
  CHECK: powershell -NoProfile -ExecutionPolicy Bypass -File tests/verify-gates.ps1 -Gate G1
  EXPECT: GATE_G1_PASS
  EVIDENCE: automatic-evidence=v1; definition-sha256=ce643c63a5819e76e5ac849e9243868aa863710664a8bacf51d0a0f534442e58; exit=0; EXPECT=matched; output-sha256=1ccd75f2002189cc14cba5c39019ebf6851d3dd902ce0d31b1737fcee2dde730; output-bytes=293; shell=C:\WINDOWS\system32\cmd.exe; cwd=C:\Users\Javeed Ahmad\Work\WIB; env-path-sha256=b7ac76c03df0; env-path-dirs=53

- [x] G2: SourceIsoHashStatus skipped is preserved on resume
  CHECK: powershell -NoProfile -ExecutionPolicy Bypass -File tests/verify-gates.ps1 -Gate G2
  EXPECT: GATE_G2_PASS
  EVIDENCE: automatic-evidence=v1; definition-sha256=a1a4012c8edc963e87ccf50f55570093adf5b64fb765082b211c714e7277e232; exit=0; EXPECT=matched; output-sha256=9df455f608be16510c2fc75b8aa24b8701aa0f93d41083f789f39baacda8f9a7; output-bytes=185; shell=C:\WINDOWS\system32\cmd.exe; cwd=C:\Users\Javeed Ahmad\Work\WIB; env-path-sha256=b7ac76c03df0; env-path-dirs=53

- [x] G3: Invalid recovery commit states rejected by ValidateSet
  CHECK: powershell -NoProfile -ExecutionPolicy Bypass -File tests/verify-gates.ps1 -Gate G3
  EXPECT: GATE_G3_PASS
  EVIDENCE: automatic-evidence=v1; definition-sha256=cc9b8861629392288fb4b7bb6eb448468b32ccf0bf2a623d8a1a3897e98ff89f; exit=0; EXPECT=matched; output-sha256=e617fce7112bb8d1efac8ee7b38719a231dbbace3b7d89b348d1ca2a87ff181b; output-bytes=14; shell=C:\WINDOWS\system32\cmd.exe; cwd=C:\Users\Javeed Ahmad\Work\WIB; env-path-sha256=b7ac76c03df0; env-path-dirs=53

- [x] G4: Crash integration test validates lock acquisition and recovery
  CHECK: powershell -NoProfile -ExecutionPolicy Bypass -File tests/verify-gates.ps1 -Gate G4
  EXPECT: GATE_G4_PASS
  EVIDENCE: automatic-evidence=v1; definition-sha256=90690f33c319978f536379bb6035a1b21e8ddd91159f81a9a4e38ee65fb62fd8; exit=0; EXPECT=matched; output-sha256=1b8eccc5d8d2b13358a84a69c8e051fe700f6043b6260411f2de2746ac0d9dc4; output-bytes=14; shell=C:\WINDOWS\system32\cmd.exe; cwd=C:\Users\Javeed Ahmad\Work\WIB; env-path-sha256=b7ac76c03df0; env-path-dirs=53

- [x] G5: Audit bundle contains smoke_results.json with passing results
  CHECK: powershell -NoProfile -ExecutionPolicy Bypass -File tests/verify-gates.ps1 -Gate G5
  EXPECT: GATE_G5_PASS
  EVIDENCE: automatic-evidence=v1; definition-sha256=76e6d4b1fef0382a57504ebe59d70a6c042a996a14ec49b195cd884cf8ca650b; exit=0; EXPECT=matched; output-sha256=c240ea3e4a6e4d636f63e09cc213e0681c8b5848b56041fc9894584b88c6f80d; output-bytes=14; shell=C:\WINDOWS\system32\cmd.exe; cwd=C:\Users\Javeed Ahmad\Work\WIB; env-path-sha256=b7ac76c03df0; env-path-dirs=53

- [x] G6: AK adaptive resume regression test suite passes
  CHECK: powershell -NoProfile -ExecutionPolicy Bypass -File tests/verify-gates.ps1 -Gate G6
  EXPECT: GATE_G6_PASS
  EVIDENCE: automatic-evidence=v1; definition-sha256=ebbe08544ded7d76c6bed650fcbdf9f5bf9ced39457a633f2311b8f26b553ea4; exit=0; EXPECT=matched; output-sha256=5a55aa1f665d5ad7d1477eed963f64c49e707ec5991ddfe583ea27979f62e0ac; output-bytes=122; shell=C:\WINDOWS\system32\cmd.exe; cwd=C:\Users\Javeed Ahmad\Work\WIB; env-path-sha256=b7ac76c03df0; env-path-dirs=53

- [x] G7: Smoke tests 100% pass across all 655 assertions
  CHECK: powershell -NoProfile -ExecutionPolicy Bypass -File tests/verify-gates.ps1 -Gate G7
  EXPECT: GATE_G7_PASS
  EVIDENCE: automatic-evidence=v1; definition-sha256=4016a42f4dab1ddb3489fe85192b262a645e47e0c89da3dfcc176a5fc0a5ebe1; exit=0; EXPECT=matched; output-sha256=c6ca5f190c753a684b39620b7c8b923203c3d112193681c9a4529582308bae7e; output-bytes=14; shell=C:\WINDOWS\system32\cmd.exe; cwd=C:\Users\Javeed Ahmad\Work\WIB; env-path-sha256=b7ac76c03df0; env-path-dirs=53

- [x] G8: Version bumped to 0.2.29 across codebase
  CHECK: powershell -NoProfile -ExecutionPolicy Bypass -File tests/verify-gates.ps1 -Gate G8
  EXPECT: GATE_G8_PASS
  EVIDENCE: automatic-evidence=v1; definition-sha256=96e5ef7d81f6acf9c41797c52947cd039275d2d1e310bfbabcba1e647b07297b; exit=0; EXPECT=matched; output-sha256=5b4fcfd09d6ffa87ee86bc39e1858ff2fe86bb3c2842d16ab717fbddc6906dec; output-bytes=14; shell=C:\WINDOWS\system32\cmd.exe; cwd=C:\Users\Javeed Ahmad\Work\WIB; env-path-sha256=b7ac76c03df0; env-path-dirs=53

- [x] G9: Transactional recovery cleanup ordering preserves authoritative ledger on failure
  CHECK: powershell -NoProfile -ExecutionPolicy Bypass -File tests/verify-gates.ps1 -Gate G9
  EXPECT: GATE_G9_PASS
  EVIDENCE: automatic-evidence=v1; definition-sha256=d9ebc01cf8f40bf9cd0e0a2b7c61b688cb34593b5a1bf48e39c6e1efe16cd2fe; exit=0; EXPECT=matched; output-sha256=f984f3336be8856286f6810967ffc1fe8c7b7d4c0cca6c827a4aad69b268fbbe; output-bytes=14; shell=C:\WINDOWS\system32\cmd.exe; cwd=C:\Users\Javeed Ahmad\Work\WIB; env-path-sha256=b7ac76c03df0; env-path-dirs=53

- [x] G10: All repository PowerShell files are 100% pure ASCII
  CHECK: powershell -NoProfile -ExecutionPolicy Bypass -File tests/verify-gates.ps1 -Gate G10
  EXPECT: GATE_G10_PASS
  EVIDENCE: automatic-evidence=v1; definition-sha256=3fb6b2d61ea9e98050cbf3318d70ceee765758a10641475226b17aa4a19c17a0; exit=0; EXPECT=matched; output-sha256=a79eba4bed21be6da20aae773bc36d06e8205b0eaa61bcf267a495dc16c6192d; output-bytes=15; shell=C:\WINDOWS\system32\cmd.exe; cwd=C:\Users\Javeed Ahmad\Work\WIB; env-path-sha256=b7ac76c03df0; env-path-dirs=53

- [x] G11: Serialized ISO publication lock, atomic replacement, and provenance coherence
  CHECK: powershell -NoProfile -ExecutionPolicy Bypass -File tests/verify-gates.ps1 -Gate G11
  EXPECT: GATE_G11_PASS
  EVIDENCE: automatic-evidence=v1; definition-sha256=e762a3411f6c84c02c12c1673c0910e6081aa063043f7805aa0342b0c30ef86d; exit=0; EXPECT=matched; output-sha256=db0c8cb367ac9b106bedcad5038533abd7079b77f4a09cdebb3800d522314de2; output-bytes=15; shell=C:\WINDOWS\system32\cmd.exe; cwd=C:\Users\Javeed Ahmad\Work\WIB; env-path-sha256=b7ac76c03df0; env-path-dirs=53

- [x] G12: Non-dry-run resumed build pipeline continuation completes and cleans up ledger
  CHECK: powershell -NoProfile -ExecutionPolicy Bypass -File tests/verify-gates.ps1 -Gate G12
  EXPECT: GATE_G12_PASS
  EVIDENCE: automatic-evidence=v1; definition-sha256=563001734f78b4171b88ea90ac02abd60cd60f710bc3ca3a08d6a6814d226588; exit=0; EXPECT=matched; output-sha256=6a058360c335b89f8f71dc8e4405320ec8346f260ec1c7a247d754a76b604096; output-bytes=4278; shell=C:\WINDOWS\system32\cmd.exe; cwd=C:\Users\Javeed Ahmad\Work\WIB; env-path-sha256=b7ac76c03df0; env-path-dirs=53

- [x] G13: Cryptographic post-mount ISO TOCTOU verification and unattend CLI security contracts
  CHECK: powershell -NoProfile -ExecutionPolicy Bypass -File tests/verify-gates.ps1 -Gate G13
  EXPECT: GATE_G13_PASS
  EVIDENCE: automatic-evidence=v1; definition-sha256=cb0ab85a096fed865d24f20c6ef045ad226e0ee9798d6d44eed0a7c767c52f8f; exit=0; EXPECT=matched; output-sha256=2079c303b9b16ce526a2a33d6485edeb051361ae1f1a19936698327a16c73d97; output-bytes=3084; shell=C:\WINDOWS\system32\cmd.exe; cwd=C:\Users\Javeed Ahmad\Work\WIB; env-path-sha256=b7ac76c03df0; env-path-dirs=53

- [x] G14: v0.2.20 audit remediation (TestOnly boundary, handle/tree reparse defense, 7-boundary fault matrix, Compact flags, ACLs, telemetry)
  CHECK: powershell -NoProfile -ExecutionPolicy Bypass -File tests/verify-gates.ps1 -Gate G14
  EXPECT: GATE_G14_PASS
  EVIDENCE: automatic-evidence=v1; definition-sha256=f050332a2cb5a413b65f5f0c77ae3de3da9b910922bc19f059ecf4d523248c53; exit=0; EXPECT=matched; output-sha256=b2851d1cdce0e907d94381d7a6b288d4a4d3ca440221240fed671ff6b1cebc06; output-bytes=2022; shell=C:\WINDOWS\system32\cmd.exe; cwd=C:\Users\Javeed Ahmad\Work\WIB; env-path-sha256=b7ac76c03df0; env-path-dirs=53

- [x] G15: v0.2.21 reassessment remediation (pre-write ACL staging & non-ACL volume rejection, File-ID concurrent mutation defense, unmanaged SecureString obscuring, and scoped process telemetry)
  CHECK: powershell -NoProfile -ExecutionPolicy Bypass -File tests/verify-gates.ps1 -Gate G15
  EXPECT: GATE_G15_PASS
  EVIDENCE: automatic-evidence=v1; definition-sha256=41d82bfe5f0115aa65d51295ce80d7c1721ede1bbf24a0574efd1a9c738917af; exit=0; EXPECT=matched; output-sha256=b37c40f13db11ac5f294277fe7628e2573a5c3f9caed0a5fc655d25c6b308c09; output-bytes=3676; shell=C:\WINDOWS\system32\cmd.exe; cwd=C:\Users\Javeed Ahmad\Work\WIB; env-path-sha256=b7ac76c03df0; env-path-dirs=53

- [x] G16: v0.2.22 audit remediation (pre-replace DACL lockdown on overwrite, Set-WibDurableJsonFile post-replace rollback, fail-closed kernel File-ID requirement, WSIM UTF-16LE PasswordHash validation, gate-check.mjs bundle inclusion, and nativeToolInvocations telemetry)
  CHECK: powershell -NoProfile -ExecutionPolicy Bypass -File tests/verify-gates.ps1 -Gate G16
  EXPECT: GATE_G16_PASS
  EVIDENCE: automatic-evidence=v1; definition-sha256=3d9301536bf64e8940ae81c3e0c24e0433d734d1fafb24d14d05eec1a376e32d; exit=0; EXPECT=matched; output-sha256=d0e242b27839c5cd90cd7dfe3fe140f70a7f68d925e6813483a178800197dab1; output-bytes=752; shell=C:\WINDOWS\system32\cmd.exe; cwd=C:\Users\Javeed Ahmad\Work\WIB; env-path-sha256=b7ac76c03df0; env-path-dirs=53

- [x] G17: v0.2.23 audit remediation (verifiable DACL fingerprint rollback & backup preservation on critical rollback failure, fail-closed compression/decompression pre-invocation identity recheck, nested nativeToolInvocations telemetry measurements, mandatory ACL prerequisites, and empty PasswordHash rejection)
  CHECK: powershell -NoProfile -ExecutionPolicy Bypass -File tests/verify-gates.ps1 -Gate G17
  EXPECT: GATE_G17_PASS
  EVIDENCE: automatic-evidence=v1; definition-sha256=a654e273b70c55e801cbc30a63fa8d453abe64c0e6e568c0718a1abe841d6e5c; exit=0; EXPECT=matched; output-sha256=fb9fbbfd7e8684b2900fe833af8b863ed3b038c0991a4abe15c34b713a489916; output-bytes=15; shell=C:\WINDOWS\system32\cmd.exe; cwd=C:\Users\Javeed Ahmad\Work\WIB; env-path-sha256=b7ac76c03df0; env-path-dirs=53

- [x] G18: v0.2.25 audit remediation (first-party native tool path resolution & mock confinement, rollback backup preservation without destructive pre-commit zeroing, reparse-point target/parent rejection & pre-replace TOCTOU verification, canonical DACL integrity validation, and accurate child process launch failure tracking)
  CHECK: powershell -NoProfile -ExecutionPolicy Bypass -File tests/verify-gates.ps1 -Gate G18
  EXPECT: GATE_G18_PASS
  EVIDENCE: automatic-evidence=v1; definition-sha256=3edc9136ebbf8fa1d13269a5ab3166bf1fc368be5e400b47835f46852325c94d; exit=0; EXPECT=matched; output-sha256=b2ffd93c03fa56b6dc19edff2590508fc64dcaa05fa657d61bcc9524c04a35b1; output-bytes=21; shell=C:\WINDOWS\system32\cmd.exe; cwd=C:\Users\Javeed Ahmad\Work\WIB; env-path-sha256=b7ac76c03df0; env-path-dirs=53

- [x] G19: v0.2.26 audit remediation (unowned collision preservation, staging validation binding, ancestor & directory ACL protection, canonical root and DACL owner integrity, and visible backup cleanup handling)
  CHECK: powershell -NoProfile -ExecutionPolicy Bypass -File tests/verify-gates.ps1 -Gate G19
  EXPECT: GATE_G19_PASS
  EVIDENCE: automatic-evidence=v1; definition-sha256=d0fb4dd85af29d557bd423595a2acfbaec073173064e75d740c945ed0f8a7369; exit=0; EXPECT=matched; output-sha256=04273e33966299783e4ba4c75ac49b3bb45ebc6d5422317f542c651c1875d728; output-bytes=545; shell=C:\WINDOWS\system32\cmd.exe; cwd=C:\Users\Javeed Ahmad\Work\WIB; env-path-sha256=b7ac76c03df0; env-path-dirs=53

- [x] G20: v0.2.27 audit remediation (atomic stage creation, handle-bound disposition deletion, on-disk owner authority, natural collision & nested junction rejection, owner rollback, and launch-time locked executable verification)
  CHECK: powershell -NoProfile -ExecutionPolicy Bypass -File tests/verify-gates.ps1 -Gate G20
  EXPECT: GATE_G20_PASS
  EVIDENCE: automatic-evidence=v1; definition-sha256=c5e839699c02890b17f023930448946e8764710269195299acdad9e7de061fed; exit=0; EXPECT=matched; output-sha256=739bc1a4c07fc665b005457c8082de794dbb325e2a0731b81ab03e05829649fc; output-bytes=15; shell=C:\WINDOWS\system32\cmd.exe; cwd=C:\Users\Javeed Ahmad\Work\WIB; env-path-sha256=b7ac76c03df0; env-path-dirs=53

- [x] G21: v0.2.28 audit remediation (mandatory kernel identity validation, unowned backup ACL preservation, single-stream stage snapshot binding, existing-target replacement race hook & rollback preservation, oscdimg strict allowlist enforcement)
  CHECK: powershell -NoProfile -ExecutionPolicy Bypass -File tests/verify-gates.ps1 -Gate G21
  EXPECT: GATE_G21_PASS
  EVIDENCE: automatic-evidence=v1; definition-sha256=2b83f2cef29810faf387c409e64eaa4013e4b203928094c7c1360fd57f9e1515; exit=0; EXPECT=matched; output-sha256=4c457bfcb90ba6c867ce04e30262d98d9c46532cc068affba9bda7f11b95bda6; output-bytes=681; shell=C:\WINDOWS\system32\cmd.exe; cwd=C:\Users\Javeed Ahmad\Work\WIB; env-path-sha256=b7ac76c03df0; env-path-dirs=53

- [x] G22: v0.2.29 audit remediation (handle-bound destination replace race closure, single-buffer immutable staging snapshot under FileShare.None, backup cleanup check-then-change race elimination, and hermetic oscdimg Authenticode & strict allowlist enforcement)
  CHECK: powershell -NoProfile -ExecutionPolicy Bypass -File tests/verify-gates.ps1 -Gate G22
  EXPECT: GATE_G22_PASS
  EVIDENCE: automatic-evidence=v1; definition-sha256=921f1133a4896f333b13227a23ffa4fdfe38b5e11b3866f104987b96b607781a; exit=0; EXPECT=matched; output-sha256=39e2e4f2019a2da372fbb08104822d3b44c3f96cf2478b0cc7557ab2a2f3287c; output-bytes=2090; shell=C:\WINDOWS\system32\cmd.exe; cwd=C:\Users\Javeed Ahmad\Work\WIB; env-path-sha256=b7ac76c03df0; env-path-dirs=53


