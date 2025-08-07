function get_bfsrc(file)
    local f = io.open(file, "r")
    if not f then error("Could not open source file: " .. file) end

    local content = f:read("*a")
    f:close()

    return content
end

local source_file = arg[1]
if not source_file then
    print("Usage: lua compiler.lua <filename.bf>")
    os.exit(1)
end

local source = get_bfsrc(source_file)
local output_ir = "output.ll"

local loop_stack = {}
local label_counter = 0

local function next_label(prefix)
    label_counter = label_counter + 1
    return prefix .. label_counter
end

local function compile_llvm(source_code, output_file)
    local f = io.open(output_file, "w")
    if not f then error("Could not open output file") end

    f:write('declare i32 @putchar(i32)\n')
    f:write('declare i32 @getchar()\n')
    f:write('@tape = common global [30000 x i8] zeroinitializer\n')
    f:write('define i32 @main() {\n')
    f:write('  %ptr_main = alloca i8*\n')
    f:write('  store i8* getelementptr inbounds ([30000 x i8], [30000 x i8]* @tape, i64 0, i64 0), i8** %ptr_main\n')
    f:write('  br label %entry\n')
    f:write('entry:\n')

    for i = 1, #source_code do
        local char = source_code:sub(i, i)
        if char == ">" then
            f:write('  %current_ptr' .. i .. ' = load i8*, i8** %ptr_main\n')
            f:write('  %new_ptr' .. i .. ' = getelementptr inbounds i8, i8* %current_ptr' .. i .. ', i64 1\n')
            f:write('  store i8* %new_ptr' .. i .. ', i8** %ptr_main\n')
        elseif char == "<" then
            f:write('  %current_ptr' .. i .. ' = load i8*, i8** %ptr_main\n')
            f:write('  %new_ptr' .. i .. ' = getelementptr inbounds i8, i8* %current_ptr' .. i .. ', i64 -1\n')
            f:write('  store i8* %new_ptr' .. i .. ', i8** %ptr_main\n')
        elseif char == "+" then
            f:write('  %current_ptr' .. i .. ' = load i8*, i8** %ptr_main\n')
            f:write('  %val' .. i .. ' = load i8, i8* %current_ptr' .. i .. '\n')
            f:write('  %new_val' .. i .. ' = add i8 %val' .. i .. ', 1\n')
            f:write('  store i8 %new_val' .. i .. ', i8* %current_ptr' .. i .. '\n')
        elseif char == "-" then
            f:write('  %current_ptr' .. i .. ' = load i8*, i8** %ptr_main\n')
            f:write('  %val' .. i .. ' = load i8, i8* %current_ptr' .. i .. '\n')
            f:write('  %new_val' .. i .. ' = sub i8 %val' .. i .. ', 1\n')
            f:write('  store i8 %new_val' .. i .. ', i8* %current_ptr' .. i .. '\n')
        elseif char == "." then
            f:write('  %current_ptr' .. i .. ' = load i8*, i8** %ptr_main\n')
            f:write('  %val' .. i .. ' = load i8, i8* %current_ptr' .. i .. '\n')
            f:write('  %extended_val' .. i .. ' = zext i8 %val' .. i .. ' to i32\n')
            f:write('  call i32 @putchar(i32 %extended_val' .. i .. ')\n')
        elseif char == "," then
            f:write('  %current_ptr' .. i .. ' = load i8*, i8** %ptr_main\n')
            f:write('  %val' .. i .. ' = call i32 @getchar()\n')
            f:write('  %truncated' .. i .. ' = trunc i32 %val' .. i .. ' to i8\n')
            f:write('  store i8 %truncated' .. i .. ', i8* %current_ptr' .. i .. '\n')
        elseif char == "[" then
            local loop_start = next_label("loop_start")
            local loop_body = "body" .. label_counter
            local loop_end = "loop_end" .. label_counter
            f:write('  br label %' .. loop_start .. '\n')
            f:write(loop_start .. ':\n')
            f:write('  %current_ptr' .. i .. ' = load i8*, i8** %ptr_main\n')
            f:write('  %val' .. i .. ' = load i8, i8* %current_ptr' .. i .. '\n')
            f:write('  %cond' .. i .. ' = icmp ne i8 %val' .. i .. ', 0\n')
            f:write('  br i1 %cond' .. i .. ', label %' .. loop_body .. ', label %' .. loop_end .. '\n')
            f:write(loop_body .. ':\n')
            table.insert(loop_stack, {start = loop_start, end_label = loop_end})
        elseif char == "]" then
            local labels = table.remove(loop_stack)
            if not labels then error("Mismatched brackets") end
            f:write('  br label %' .. labels.start .. '\n')
            f:write(labels.end_label .. ':\n')
        end
    end

    if #loop_stack > 0 then error("Unmatched brackets") end

    f:write('  ret i32 0\n')
    f:close()
end

compile_llvm(source, output_ir)

os.execute("clang " .. output_ir .. " -o bf_program && rm " .. output_ir)
