# Suggested addition to the existing GitHub README

Append the following section to the existing repository-level `README.md` after the installer and HTML guides are committed. Do not replace the project's README with the installer package README.

---

## Getting started

Clone JAWS:

    git clone https://github.com/The-John-Charitable-Trust/Jaws.git
    cd Jaws

- [Installation Guide (HTML)](docs/installation/index.html)
- [Architecture and Development Tutorial](docs/tutorial/)
- [Manual Verification Guide (HTML)](docs/verification/index.html)

**Release status:** `Install-Jaws.ps1` supports Discover, Plan, and Package. It does not provision a new cloud installation. The dev-project install through Step C is `installer/Install-JawsThroughStepC.ps1` (`-Mode Validate` reads Azure and writes nothing; `-Mode Install -AcknowledgeStepCInstall` repairs only known gaps). See `docs/installation/STEP-C-RUNBOOK.md`.
