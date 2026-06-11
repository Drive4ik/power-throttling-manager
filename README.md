<h1>
    <img src="icon.svg" width="64"> Power Throttling Manager
</h1>

A small Windows utility that lets you manage per-app **Power Throttling** exemptions via a GUI — without touching the command line.
It wraps `powercfg /powerthrottling` and persists the list across reboots, supports Win32 EXEs and Store apps (by PFN), and requires elevation to write power policy.
