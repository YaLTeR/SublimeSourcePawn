#pragma semicolon 1

#include <profiler>

public Plugin:myinfo =
{
	name = "SublimeText2 snippet generator",
	author = "MCPAN (mcpan@foxmail.com)",
	version = "1.0.0.3",
	url = "https://forums.alliedmods.net/member.php?u=73370"
}

//#define __DEBUG_MODE__
#if defined __DEBUG_MODE__

new Handle:g_FuncList;
new Handle:g_DefineList;
new Handle:g_EnumList;

new Handle:g_PathTrie;
new Handle:g_DefineAarray;
new Handle:g_EnmuAarray;
#endif // __DEBUG_MODE__

enum BufferType
{
	Type_Define,
	Type_Enum,

	Type_Stock,
	Type_Native,
	Type_Forward,
	Type_Functag
}

new String:PATH_SNIPPET[PLATFORM_MAX_PATH];
new const String:PATH_INCLUDE[] = "addons/sourcemod/scripting/include";

public OnPluginStart()
{
	RegServerCmd("test", Cmd_Start);
}

public Action:Cmd_Start(argc)
{
	new Handle:prof = CreateProfiler();
	StartProfiling(prof);

	new size, Handle:fileArray = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));
	if (!(size = ReadDirFileList(fileArray, PATH_INCLUDE, "inc")))
	{
		CloseHandle(fileArray);
		CloseHandle(prof);
		PrintToServer("No include file in path '%s'", PATH_INCLUDE);
		return Plugin_Handled;
	}

	FormatTime(PATH_SNIPPET, sizeof(PATH_SNIPPET), "addons/sourcemod/plugins/sourcepawn_sublime_snippet_%Y%m%d%H%M%S");
	CreateDirectory(PATH_SNIPPET, 511);

#if defined __DEBUG_MODE__
	g_FuncList = OpenFile("addons/sourcemod/plugins/testfile_allfunc.sp", "wt");
	g_DefineList = OpenFile("addons/sourcemod/plugins/testfile_alldef.sp", "wt");
	g_EnumList = OpenFile("addons/sourcemod/plugins/testfile_allenum.sp", "wt");

	g_PathTrie = CreateTrie();
	g_DefineAarray = CreateArray(ByteCountToCells(128));
	g_EnmuAarray = CreateArray(ByteCountToCells(128));
#endif

	decl String:buffer[PLATFORM_MAX_PATH];
	for (new x; x < size; x++)
	{
		GetArrayString(fileArray, x, buffer, sizeof(buffer));
		ReadIncludeFile(buffer);
	}

	CloseHandle(fileArray);

#if defined __DEBUG_MODE__
	if ((size = GetArraySize(g_DefineAarray)))
	{
		//decl String:filename[PLATFORM_MAX_PATH];
		SortADTArray(g_DefineAarray, Sort_Ascending, Sort_String);
		for (new x = 0; x < size; x++)
		{
			GetArrayString(g_DefineAarray, x, buffer, sizeof(buffer));
			WriteFileLine(g_DefineList, "%s", buffer);

			//GetTrieString(g_PathTrie, buffer, filename, sizeof(filename));
			//GetFileBaseName(filename, filename, sizeof(filename));
			//WriteFileLine(g_DefineList, "%s\t\t//%s", buffer, filename);
		}
	}

	if ((size = GetArraySize(g_EnmuAarray)))
	{
		SortADTArray(g_EnmuAarray, Sort_Ascending, Sort_String);
		for (new x = 0; x < size; x++)
		{
			GetArrayString(g_EnmuAarray, x, buffer, sizeof(buffer));
			WriteFileLine(g_EnumList, "%s", buffer);
		}
	}

	CloseHandle(g_FuncList);
	CloseHandle(g_DefineList);
	CloseHandle(g_EnumList);

	CloseHandle(g_PathTrie);
	CloseHandle(g_DefineAarray);
	CloseHandle(g_EnmuAarray);
#endif

	StopProfiling(prof);
	PrintToServer("\nDone. time used %fs", GetProfilerTime(prof));
	CloseHandle(prof);

	return Plugin_Handled;
}

ReadIncludeFile(String:filepath[])
{
	new Handle:file;
	if ((file = OpenFile(filepath, "rt")) == INVALID_HANDLE)
	{
		LogError("Open file faild '%s'", filepath);
		return;
	}

	new pos, bool:found_comment, bool:found_enum;
	decl String:buffer[512], String:enumcontents[4096];

	while (ReadFileLine(file, buffer, sizeof(buffer)))
	{
		if (!ReadString(buffer, sizeof(buffer), found_comment) || found_comment)
		{
			continue;
		}

		if (!strncmp(buffer, "#define", 7))
		{
			strcopy(buffer, sizeof(buffer), buffer[7 + 1]);
			TrimString(buffer);

			if ((pos = FindCharInString(buffer, ' ')) != -1)
			{
				buffer[pos] = 0;
			}

			if (StrContains(buffer, "_included") != -1 ||
				FindCharInString(buffer, '[') != -1 ||
				FindCharInString(buffer, '(') != -1)
			{
				continue;
			}

			WriteSnippetFile(filepath, buffer, Type_Define);
#if defined __DEBUG_MODE__
			if (FindStringInArray(g_DefineAarray, buffer) == -1)
			{
				PushArrayString(g_DefineAarray, buffer);
				SetTrieString(g_PathTrie, buffer, filepath);
			}
#endif
		}
		else if (!strncmp(buffer, "enum", 4) && !found_enum)
		{
			found_enum = true;
			enumcontents[0] = 0;
		}
		else if (!strncmp(buffer, "#pragma deprecated", 18))
		{
			if (ReadFileLine(file, buffer, sizeof(buffer)) && !strncmp(buffer, "stock", 5))
			{
				SkipBraceLine(file, buffer, sizeof(buffer));
			}
		}
		else if (!strncmp(buffer, "native", 6))
		{
			GetFullFunctionString(file, filepath, buffer, sizeof(buffer), Type_Native);
		}
		else if (!strncmp(buffer, "stock", 5))
		{
			GetFullFunctionString(file, filepath, buffer, sizeof(buffer), Type_Stock);
			SkipBraceLine(file, buffer, sizeof(buffer));
		}
		else if (!strncmp(buffer, "forward", 7) )
		{
			GetFullFunctionString(file, filepath, buffer, sizeof(buffer), Type_Forward);
		}
		else if (!strncmp(buffer, "functag", 7))
		{
			GetFullFunctionString(file, filepath, buffer, sizeof(buffer), Type_Functag);
		}

		if (found_enum)
		{
			if ((pos = FindCharInString(buffer, '}')) != -1)
			{
				buffer[pos] = 0;
				found_enum = false;
			}

			Format(enumcontents, sizeof(enumcontents), "%s%s", enumcontents, buffer);

			if (!found_enum)
			{
				strcopy(enumcontents, sizeof(enumcontents), enumcontents[FindCharInString(enumcontents, '{') + 1]);

				new idx, bool:ignore;
				for (new x = 0; x < strlen(enumcontents); x++)
				{
					switch (enumcontents[x])
					{
						case '=', ' ' :
						{
							ignore = true;
						}
						case ':' :
						{
							buffer[0] = idx = 0;
							continue;
						}
						case ',' :
						{
							if (buffer[0])
							{
								WriteSnippetFile(filepath, buffer, Type_Enum);
#if defined __DEBUG_MODE__
								if (FindStringInArray(g_EnmuAarray, buffer) == -1)
								{
									PushArrayString(g_EnmuAarray, buffer);
									SetTrieString(g_PathTrie, buffer, filepath);
								}
#endif
							}

							ignore = false;
							buffer[0] = idx = 0;
							continue;
						}
					}

					if (!ignore)
					{
						buffer[idx] = enumcontents[x];
						buffer[++idx] = 0;
					}
				}

				if (buffer[0])
				{
					WriteSnippetFile(filepath, buffer, Type_Enum);
#if defined __DEBUG_MODE__
					if (FindStringInArray(g_EnmuAarray, buffer) == -1)
					{
						PushArrayString(g_EnmuAarray, buffer);
						SetTrieString(g_PathTrie, buffer, filepath);
					}
#endif
				}
			}
		}
	}

	CloseHandle(file);
}

GetFullFunctionString(Handle:file, String:filepath[], String:buffer[], maxlength, BufferType:type)
{
	new pos, multi_line;
	decl String:temp[512], String:fullfuncstr[512];

	do
	{
		TrimString(buffer);
		if ((pos = FindCharInString(buffer, ')', true)) != -1)
		{
			strcopy(fullfuncstr, pos + 2, buffer); //remove ')'

			if (multi_line)
			{
				Format(fullfuncstr, maxlength, "%s%s", temp, fullfuncstr);
			}

			break;
		}

		multi_line++;
		Format(temp, sizeof(temp), "%s%s", temp, buffer);
	}
	while (ReadFileLine(file, buffer, maxlength));

	if (!IsDeprecatedFunc(fullfuncstr))
	{
#if defined __DEBUG_MODE__
		WriteFileLine(g_FuncList, fullfuncstr);
#endif
		WriteSnippetFile(filepath, fullfuncstr, type);
	}
}

WriteSnippetFile(String:filepath[], String:buffer[], BufferType:type)
{
	new pos;
	decl String:temp[512];
	decl String:content[512];
	decl String:tabTrigger[256];
	decl String:snippetPath[256];

	switch (type)
	{
		case Type_Define :
		{
			strcopy(content, sizeof(content), buffer);
			strcopy(tabTrigger, sizeof(tabTrigger), buffer);
			FormatEx(snippetPath, sizeof(snippetPath), "define_%s", buffer);
		}
		case Type_Enum :
		{
			strcopy(content, sizeof(content), buffer);
			strcopy(tabTrigger, sizeof(tabTrigger), buffer);
			FormatEx(snippetPath, sizeof(snippetPath), "enum_%s", buffer);
		}
		case Type_Stock, Type_Native :
		{
			decl String:paramstr[512]; paramstr[0] = 0;
			strcopy(temp, (pos = FindCharInString(buffer, '(')) + 1, buffer);
			strcopy(paramstr, sizeof(paramstr), buffer[pos]);
			ReplaceSymbol(temp, snippetPath, sizeof(snippetPath));

			if ((pos = FindCharInString(temp, ':')) == -1)
			{
				pos = FindCharInString(temp, ' ', true); // if doesnt have tag, reverse search space.
			}

			strcopy(tabTrigger, sizeof(tabTrigger), temp[++pos]);
			FormatParamString(paramstr, temp, sizeof(temp));
			FormatEx(content, sizeof(content), "%s(%s)", tabTrigger, temp);

			if (IsCharUpper(tabTrigger[0]))
			{
				tabTrigger[0] = CharToLower(tabTrigger[0]);
			}
		}
		case Type_Forward :
		{
			decl String:funcstrReplaced[512];
			strcopy(funcstrReplaced, sizeof(funcstrReplaced), buffer);
			ReplaceStringEx(funcstrReplaced, sizeof(funcstrReplaced), "forward", "public", 7);

			FormatEx(content, sizeof(content), "%s\n{\n\t${1:/* code */}\n}", funcstrReplaced);
			strcopy(tabTrigger, FindCharInString(funcstrReplaced, '(') + 1, funcstrReplaced);

			ReplaceSymbol(tabTrigger, snippetPath, sizeof(snippetPath));
		}
		case Type_Functag :
		{
			decl String:funcstrReplaced[512];
			strcopy(funcstrReplaced, sizeof(funcstrReplaced), buffer[7 + 1]); //remove "functag"
			TrimString(funcstrReplaced);

			if ((pos = StrContains(funcstrReplaced, " public(")) != -1)
			{
				strcopy(temp, pos + 1, funcstrReplaced); TrimString(temp);
				strcopy(funcstrReplaced, sizeof(funcstrReplaced), funcstrReplaced[pos + 7]);
				Format(funcstrReplaced, sizeof(funcstrReplaced), "public %s%s", temp, funcstrReplaced);
			}
			else if ((pos = StrContains(funcstrReplaced, ":public(")) != -1)
			{
				decl String:func_tag[32];
				strcopy(temp, pos + 1, funcstrReplaced); TrimString(temp);
				strcopy(funcstrReplaced, sizeof(funcstrReplaced), funcstrReplaced[pos + 7]);

				pos = FindCharInString(temp, ' ', true);
				strcopy(func_tag, sizeof(func_tag), temp[pos + 1]); temp[pos] = 0; TrimString(temp);
				Format(funcstrReplaced, sizeof(funcstrReplaced), "public %s:%s%s", func_tag, temp, funcstrReplaced);
			}

			if (strncmp(funcstrReplaced, "public", 6) != 0)
			{
				Format(funcstrReplaced, sizeof(funcstrReplaced), "public %s", funcstrReplaced);
			}

			FormatEx(content, sizeof(content), "%s\n{\n\t${1:/* code */}\n}", funcstrReplaced);
			strcopy(tabTrigger, FindCharInString(funcstrReplaced, '(') + 1, funcstrReplaced);

			ReplaceSymbol(tabTrigger, snippetPath, sizeof(snippetPath));
		}
	}

	ReplaceString(content, sizeof(content), "\"", "\\\"");
	Format(snippetPath, sizeof(snippetPath), "%s/%s.sublime-snippet", PATH_SNIPPET, snippetPath);

	decl String:filename[PLATFORM_MAX_PATH];
	new Handle:file = OpenFile(snippetPath, "wt");
	GetFileBaseName(filepath, filename, sizeof(filename));
	WriteFileLine(file, "<snippet>");
	WriteFileLine(file, "\t<description>%s</description>", filename);
	WriteFileLine(file, "\t<content><![CDATA[%s]]></content>", content);
	WriteFileLine(file, "\t<tabTrigger>%s</tabTrigger>", tabTrigger);
	WriteFileLine(file, "\t<scope>source.sp, source.inc</scope>");
	WriteFileLine(file, "</snippet>");
	CloseHandle(file);
}

FormatParamString(String:paramstr[], String:output[], maxlength)
{
	new pos;
	strcopy(output, maxlength, paramstr[FindCharInString(paramstr, '(') + 1]);
	if ((pos = FindCharInString(output, ')', true)) != -1)
	{
		output[pos] = 0;
	}

	TrimString(output);
	if (!output[0])
	{
		return 0;
	}

	// fix comma in ExplodeString bug
	new num_brace;
	for (new x; x < strlen(output); x++)
	{
		switch (output[x])
		{
			case '{' : num_brace++;
			case '}' : num_brace--;
			case ',' :
			{
				if (num_brace)
				{
					output[x] = '|';
				}
			}
		}
	}

	decl String:parts[32][64];
	new num_params = ExplodeString(output, ",", parts, sizeof(parts), sizeof(parts[]));
	output[0] = 0;

	while (num_params)
	{
		if (FindCharInString(parts[num_params-1], '=') == -1
		&& StrContains(parts[num_params-1], "any:...") == -1)
		{
			break;
		}

		num_params--;
	}

	if (num_params)
	{
		decl String:temp[64];
		for (new x; x < num_params; x++)
		{
			strcopy(temp, sizeof(temp), parts[x][FindCharInString(parts[x], '=') + 1]);

			if ((pos = FindCharInString(temp, '[')) != -1 && temp[pos+1] == ']'
			||	(pos = FindCharInString(temp, ']')) != -1)
			{
				temp[pos] = 0;
			}

			TrimString(temp);
			ReplaceSymbol(temp, temp, sizeof(temp));
			Format(output, maxlength, "%s%s${%i:%s}", output, x ? ", " : "", x + 1, temp);
		}
	}

	return num_params;
}

ReplaceSymbol(String:input[], String:output[], maxlength)
{
	new len;
	if (!(len = strlen(input)))
	{
		return;
	}

	if (len > maxlength)
	{
		len = maxlength;
	}

	strcopy(output, maxlength, input);

	for (new x; x < len; x++)
	{
		switch (output[x])
		{
			case ' ', ':', '&', '[' /*, '\\', '/', '*', '?', '"', '<', '>'*/ :
			{
				output[x] = '_';
			}
			case '|' :
			{
				output[x] = ',';
			}
		}
	}
}


bool:IsDeprecatedFunc(String:funcstr[])
{
	return !strncmp(funcstr, "native VerifyCoreVersion(", 25)
		|| !strncmp(funcstr, "native Float:operator*", 22)
		|| !strncmp(funcstr, "native Float:operator/", 22)
		|| !strncmp(funcstr, "native Float:operator+", 22)
		|| !strncmp(funcstr, "native Float:operator-", 22)

		|| !strncmp(funcstr, "stock Float:operator*", 21)
		|| !strncmp(funcstr, "stock Float:operator/", 21)
		|| !strncmp(funcstr, "stock Float:operator+", 21)
		|| !strncmp(funcstr, "stock Float:operator-", 21)

		|| !strncmp(funcstr, "stock bool:operator=", 20)
		|| !strncmp(funcstr, "stock bool:operator!", 20)
		|| !strncmp(funcstr, "stock bool:operator>", 20)
		|| !strncmp(funcstr, "stock bool:operator<", 20)

		|| !strncmp(funcstr, "forward operator%(", 18);
}

SkipBraceLine(Handle:file, String:buffer[], maxlength)
{
	new x, num_brace, bool:found;
	do
	{
		for (x = 0; x < strlen(buffer); x++)
		{
			switch (buffer[x])
			{
				case '{' : num_brace++, found = true;
				case '}' : num_brace--;
			}
		}

		if (!found)
		{
			continue;
		}

		if (!num_brace)
		{
			break;
		}
	}
	while (ReadFileLine(file, buffer, maxlength));
}

ReadString(String:buffer[], maxlength, &bool:found_comment=false)
{
	ReplaceString(buffer, maxlength, "\t", " ");

	new len;
	if ((len = strlen(buffer)) && !found_comment)
	{
		for (new x; x < len; x++)
		{
			if (buffer[x] == '/' && buffer[x + 1] == '/')
			{
				buffer[x] = 0;
				break;
			}
		}
	}

	TrimString(buffer);
	new bool:comment_start, bool:comment_end;

	if ((len = strlen(buffer)))
	{
		new pos;
		decl String:temp[512];
		if ((pos = StrContains(buffer, "/*")) != -1)
		{
			comment_start = true;
			strcopy(temp, sizeof(temp), buffer[pos + 2]);
			buffer[pos] = 0;
			TrimString(buffer);

			if ((pos = StrContains(temp, "*/")) != -1)
			{
				comment_end = true;
				strcopy(temp, sizeof(temp), temp[pos + 2]);
				TrimString(temp);
			}
			else
			{
				temp[0] = 0;
			}

			if (buffer[0] || temp[0])
			{
				Format(buffer, maxlength, "%s%s", buffer, temp);
			}
		}
		else if ((pos = StrContains(buffer, "*/")) != -1)
		{
			comment_end = true;
			strcopy(buffer, maxlength, buffer[pos+2]);
		}

		TrimString(buffer);
		len = strlen(buffer);
	}

	if (comment_start && comment_end)
	{
		comment_start = false;
		comment_end = false;
	}

	if (comment_start || comment_end)
	{
		found_comment = comment_start;
	}

	return len;
}

stock ReadDirFileList(&Handle:fileArray, const String:dirPath[], const String:fileExt[]="")
{
	new Handle:dir;
	if ((dir = OpenDirectory(dirPath)) == INVALID_HANDLE)
	{
		LogError("Open dir faild '%s'", dirPath);
		return 0;
	}

	new FileType:fileType;
	decl String:buffer[PLATFORM_MAX_PATH];
	decl String:currentPath[PLATFORM_MAX_PATH];
	new Handle:pathArray = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));

	buffer[0] = currentPath[0] = 0;

	while (ReadDirEntry(dir, buffer, sizeof(buffer), fileType)
		|| ReadSubDirEntry(dir, buffer, sizeof(buffer), fileType, pathArray, dirPath, currentPath))
	{
		switch (fileType)
		{
			case FileType_Directory:
			{
				if (!strcmp(buffer, ".") || !strcmp(buffer, ".."))
				{
					continue;
				}

				Format(buffer, sizeof(buffer), "%s/%s", currentPath, buffer);
				PushArrayString(pathArray, buffer);
			}
			case FileType_File:
			{
				if (fileExt[0] && !CheckFileExt(buffer, fileExt))
				{
					continue;
				}

				Format(buffer, sizeof(buffer), "%s%s/%s", dirPath, currentPath, buffer);
				PushArrayString(fileArray, buffer);
			}
		}
	}

	CloseHandle(pathArray);
	if (dir != INVALID_HANDLE)
	{
		CloseHandle(dir);
	}

	return GetArraySize(fileArray);
}

stock bool:ReadSubDirEntry(&Handle:dir, String:buffer[], maxlength, &FileType:fileType, &Handle:pathArray, const String:dirPath[], String:currentPath[])
{
	CloseHandle(dir);
	dir = INVALID_HANDLE;

	if (!GetArraySize(pathArray))
	{
		return false;
	}

	GetArrayString(pathArray, 0, currentPath, maxlength);
	RemoveFromArray(pathArray, 0);

	FormatEx(buffer, maxlength, "%s%s", dirPath, currentPath);
	if ((dir = OpenDirectory(buffer)) == INVALID_HANDLE)
	{
		LogError("Open sub dir faild '%s'", buffer);
		return false;
	}

	return ReadDirEntry(dir, buffer, maxlength, fileType);
}

stock bool:CheckFileExt(String:filename[], const String:extname[])
{
	new pos;
	if ((pos = FindCharInString(filename, '.', true)) == -1)
	{
		return false;
	}

	decl String:ext[32];
	strcopy(ext, sizeof(ext), filename[++pos]);
	return !strcmp(ext, extname, false);
}

stock GetFileBaseName(String:filepath[], String:filename[], maxlength, bool:removeExt = true)
{
	decl String:str[PLATFORM_MAX_PATH];
	strcopy(str, sizeof(str), filepath);
	ReplaceString(str, sizeof(str), PATH_INCLUDE, "");

	if (str[0] == '/')
	{
		strcopy(str, sizeof(str), str[1]);
	}

	new pos;
	if (removeExt && (pos = FindCharInString(str, '.', true)) != -1)
	{
		str[pos] = 0;
	}

	return strcopy(filename, maxlength, str);
}
