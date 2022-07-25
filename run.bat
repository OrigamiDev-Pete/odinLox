@echo off

if not exist \bin mkdir \bin
odin build src -out:bin/lox.exe
.\bin\lox.exe %*