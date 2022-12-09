@echo off

if not exist \bin mkdir \bin
odin build src -out:bin/lox.exe -o:speed
.\bin\lox.exe %*