@echo off
set /p SKILL=<my_config.md
gemini -i "%SKILL%" --sandbox false "%*"