# JAWS Installation — GitHub-first setup (Stage A preview)

Open [`index.html`](index.html) for the illustrated, expandable installation guide.

Published installation sources are obtained from the GitHub repository:

```powershell
Set-Location "$HOME\Documents"
git clone https://github.com/cezjah/Jaws.git
Set-Location .\Jaws
```

The published repository must contain the installer, documents and tests. No second ZIP download, overlay, or manual folder merge is part of the end-user installation workflow.

**Stage A only:** ` .\installer\Install-Jaws.ps1 -Mode Discover ` performs read-only inventory and creates local reports. It cannot install JAWS into an empty environment. `-Mode Install` will be implemented and documented in Stage B.

The repository may currently require GitHub access.
