# Used by digest_chats.sh. Args: $mode ("cc" = Claude Code JSONL stream, "export" = claude.ai conversations.json),
# $src (source path), $sess (session id for cc), $minturns (number).
# Emits one compact JSON object per conversation: {name, kind, date, title, turns, errors, chars, cwd, source, md}

def txt: if type == "string" then .
         elif type == "array" then map(select(type == "object" and .type == "text") | .text) | join("\n")
         else "" end;
def clip($n): if length > $n then .[0:$n] + " [...]" else . end;
def oneline: gsub("\n"; " ; ");
def noise: test("^\\s*<(local-command-stdout|local-command-stderr|system-reminder|command-message|command-args)");
def has($x): any(.[]; . == $x);
def slug: ascii_downcase | gsub("[^a-z0-9]+"; "-") | ltrimstr("-") | rtrimstr("-") | .[0:50] | if . == "" then "untitled" else . end;
def newturn($time; $user): {time: $time, user: $user, cmds: [], files: [], errors: [], answer: ""};

def render($kind; $session; $started; $cwd; $title):
  .turns as $T
  | ($T | map(.errors | length) | add // 0) as $nerr
  | (([ "---", "source: \($src)", "kind: \($kind)", "session: \($session)", "started: \($started)",
       "cwd: \($cwd)", "turns: \($T | length)", "errors: \($nerr)", "decision: ", "---", "# \($title)", "" ]
     + [ $T | to_entries[] | .key as $k | .value as $t
         | "## Turn \($k + 1) (\($t.time))",
           "**User:** \($t.user | clip(1500))",
           (if ($t.cmds | length) > 0 then
              "**Commands (\($t.cmds | length)):**",
              ($t.cmds[0:15][] | "- `\(oneline)`"),
              (if ($t.cmds | length) > 15 then "- ... \(($t.cmds | length) - 15) more" else empty end)
            else empty end),
           (if ($t.files | length) > 0 then "**Files written:** " + ($t.files[0:20] | map("`\(.)`") | join(", ")) else empty end),
           ($t.errors[] | "- ERROR `\(.cmd | oneline)`: \(.err | gsub("\n"; " "))"
                          + (if .fix then "\n  - next OK: `\(.fix | oneline)`" else "" end)),
           (if $t.answer != "" then "**Result:** \($t.answer | clip(1200))" else empty end),
           "" ]) | join("\n")) as $md
  | (($started // "")[0:10] | if . == "" then "0000-00-00" else . end) as $date
  | {name: "\($date)_\($title | slug)_\($session[0:8]).md", kind: $kind, date: $date, title: $title,
     turns: ($T | length), errors: $nerr, chars: ($md | length), cwd: $cwd, source: $src, md: $md};

def cc_state:
  reduce (inputs | select((.isSidechain | not) and (.isMeta | not))) as $e (
    {turns: [], pending: {}, cwd: "", started: ""};
    (if .cwd == "" then .cwd = ($e.cwd // "") else . end)
    | (if .started == "" then .started = (($e.timestamp // "")[0:19]) else . end)
    | ($e.message.content) as $c
    | ((.turns | length) - 1) as $i
    | if $e.type == "user" then
        [ $c | if type == "array" then .[] else empty end | select(type == "object" and .type == "tool_result") ] as $res
        | if ($res | length) > 0 then
            if $i >= 0 then
              reduce $res[] as $r (.;
                ($r.tool_use_id // "") as $id
                | (.pending[$id] // null) as $cmd
                | .pending |= del(.[$id])
                | if $r.is_error == true then
                    .turns[$i].errors += [{cmd: ($cmd // ""), err: ($r.content | txt | clip(300)), fix: null}]
                  elif $cmd != null and (.turns[$i].errors | length) > 0 and .turns[$i].errors[-1].fix == null then
                    .turns[$i].errors[(.turns[$i].errors | length) - 1].fix = $cmd
                  else . end)
            else . end
          else
            ($c | txt) as $t
            | if ($t | test("\\S")) and (($t | noise) | not)
              then .turns += [newturn(($e.timestamp // "")[0:16]; $t)] else . end
          end
      elif $e.type == "assistant" and $i >= 0 then
        reduce ($c | if type == "array" then .[] else empty end | select(type == "object")) as $b (.;
          if $b.type == "text" and (($b.text // "") | test("\\S")) then .turns[$i].answer = $b.text
          elif $b.type == "tool_use" then
            ($b.input // {}) as $in
            | if (["Bash", "bash", "shell", "run_command"] | has($b.name)) and ($in.command != null) then
                ($in.command | clip(200)) as $cmd
                | .turns[$i].cmds += [$cmd] | .pending[$b.id // ""] = $cmd
              elif (["Write", "Edit", "MultiEdit", "NotebookEdit", "create_file", "str_replace"] | has($b.name))
                   and (($in.file_path // $in.path) != null) then
                ($in.file_path // $in.path) as $fp
                | if (.turns[$i].files | has($fp)) then . else .turns[$i].files += [$fp] end
              else . end
          else . end)
      else . end);

if $mode == "cc" then
  cc_state
  | select((.turns | length) >= $minturns)
  | render("claude-code"; $sess; .started; .cwd;
           (if (.turns | length) > 0 then (.turns[0].user | split("\n")[0] | clip(80)) else $sess end))
else
  input | (if type == "array" then .[] else empty end)
  | select(.chat_messages != null) | . as $c
  | reduce .chat_messages[] as $m ({turns: []};
      (($m.text // "") | if . == "" then ($m.content | txt) else . end) as $t
      | if $m.sender == "human" then .turns += [newturn(($m.created_at // "")[0:16]; $t)]
        elif (.turns | length) > 0 and ($t | test("\\S")) then .turns[(.turns | length) - 1].answer = $t
        else . end)
  | select((.turns | length) >= $minturns)
  | render("claude.ai"; ($c.uuid // ""); (($c.created_at // "")[0:19]); "";
           (($c.name // "") | if . == "" then ($c.chat_messages[0].text // "untitled" | clip(80)) else . end))
end
