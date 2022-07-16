@echo off

if not exist \bin mkdir \bin
odin build src -debug -out:bin/lox.exe
echo Debug build complete.

echo Opening Visual Studio
devenv bin/lox.exe %*