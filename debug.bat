@echo off

odin build src -debug -out:odinLox.exe
echo Debug build complete.

devenv odinLox.exe