@echo off

if not exist \bin mkdir \bin
odin build src -out:bin/lox.exe -opt:3
.\bin\lox.exe %*