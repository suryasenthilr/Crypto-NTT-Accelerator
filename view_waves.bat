@echo off
cd /d "%~dp0"
call "C:\Users\surya\.oss-cad-suite\oss-cad-suite\environment.bat"
start "" gtkwave "sim\polyflex_top.vcd"
