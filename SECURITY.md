# Security Policy

The Windows Image Builder (WIB) team takes security and offline image integrity seriously. This document outlines supported versions and our responsible disclosure policy.

---

## Supported Versions

Security updates and bug fixes are applied to the latest minor release line:

| Version | Supported | Notes |
| :--- | :---: | :--- |
| **0.2.x** | **Yes** | Active release line (Current: `v0.2.29`). Receives security and integrity fixes. |
| **< 0.2.0** | No | Legacy versions. Please upgrade to the latest release. |

---

## Reporting a Vulnerability

> [!CAUTION]
> **Do NOT report security vulnerabilities through public GitHub issues, discussions, or pull requests.** Public disclosure before a fix is available can put users and environments at risk.

### Preferred Reporting Method
Please submit security reports using **GitHub Private Vulnerability Reporting**:
1. Navigate to the repository's **Security** tab on GitHub.
2. Select **Advisories** from the left navigation menu.
3. Click **Report a vulnerability** to open a private draft advisory with the maintainers.

### Maintainer Notice & Alternative Contact
If GitHub Private Vulnerability Reporting is not yet active on this repository:
* **Maintainer Action Item:** [Configure GitHub Private Vulnerability Reporting](https://docs.github.com/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability) in repository settings.
* Alternatively, contact the project maintainer privately via GitHub profile contact details.

---

## What to Include in Your Report

To help us triage and resolve the issue quickly, please include:
1. **Summary:** A clear description of the vulnerability, affected components, and potential impact.
2. **Threat Model:** Explain how the vulnerability could be exploited (e.g., privilege escalation, symlink traversal, TOCTOU replacement, or credential disclosure).
3. **Reproduction Steps:** A minimal, reproducible proof-of-concept (PoC) script or detailed step-by-step instructions.
4. **Environment:** OS build version (`winver`), PowerShell version (`$PSVersionTable.PSVersion`), and execution rights (elevated vs non-elevated).
5. **Mitigation Suggestion:** Any suggested patches or defensive controls, if available.

---

## Response & Disclosure Process

* **Acknowledgment:** Maintainers strive to acknowledge receipt of security reports within **48 to 72 hours**.
* **Assessment & Fix:** We will evaluate the report, verify the vulnerability, and collaborate on a private fix via a security advisory fork.
* **Coordinated Disclosure:** A CVE identifier (if applicable) and patched release will be coordinated with the reporter before publishing advisory details.

---

## Security Scope & Operational Context

* **First-Party Tooling:** WIB relies on native Windows tools (`dism.exe`, `reg.exe`) and signed Microsoft ADK binaries (`oscdimg.exe`). Vulnerabilities within Microsoft binaries themselves should be reported directly to the [Microsoft Security Response Center (MSRC)](https://www.microsoft.com/msrc).
* **Unattended Credentials:** Passwords stored in `autounattend.xml` answer files are obfuscated with standard WSIM Base64 (`<PlainText>false</PlainText>`). This format is reversible and is **not equivalent to cryptographic encryption**. Anyone with read access to the installation media or the answer file can recover the password. Always use temporary, unique credentials for initial setup, restrict physical and network media access, and rotate or remove the temporary administrator account immediately after setup.
