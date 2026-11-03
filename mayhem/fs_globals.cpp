// Globals that foldseek's src/foldseek.cpp defines for the mmseqs framework; the harnesses need them
// without that file's command registration and without a second main().
#include "LocalParameters.h"

const char* binary_name = "foldseek";
const char* tool_name = "foldseek";
const char* tool_introduction = "foldseek fuzz harness";
const char* main_author = "";
const char* show_extended_help = "1";
const char* show_bash_info = NULL;
const char* index_version_compatible = "fs1";
bool hide_base_commands = true;
bool hide_base_downloads = true;
void initParameterSingleton() { new LocalParameters; }
