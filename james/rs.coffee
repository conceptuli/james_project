

class JsRiveObjects
  constructor: (master) ->
    @_master = master
    @_objects = {} # Cache of objects.




  #//////////////////////////////////////////////////////////////////////////
  # Constructor and Debug Methods                                          //
  #//////////////////////////////////////////////////////////////////////////

  # Constants.

  ###*
  RiveScript (hash options)

  Create a new RiveScript interpreter. options is a hash:

  bool debug:     Debug mode            (default false)
  int  depth:     Recursion depth limit (default 50)
  bool strict:    Strict mode           (default true)
  str  debug_div: ID of an element to write debug lines to (optional)
  ###
  class RiveScript
    constructor: (opts) ->

    # Defaults.
      @_debug = false
      @_strict = true
      @_depth = 50
      @_div = `undefined`

      # Identify our runtime environment. Web, or NodeJS?
      @_node = {} # NodeJS objects
      @_runtime = @runtime()

      # Loading files in will be asynchronous, so we'll need to be able to
      # identify when we've finished loading files! This will be an object
      # to keep track of which files are still pending.
      @_pending = []
      @_loadcount = 0 # For multiple calls to loadFile...

      # Internal data structures.
      @_gvars = {} # 'global' variables
      @_bvars = {} # 'bot' variables
      @_subs = {} # 'sub' substitutions
      @_person = {} # 'person' substitutions
      @_arrays = {} # 'array' variables
      @_users = {} # 'user' variables
      @_freeze = {} # frozen 'user' variables
      @_includes = {} # included topics
      @_lineage = {} # inherited topics
      @_handlers = {} # object handlers
      @_objlangs = {} # languages of objects used
      @_topics = {} # main reply structure
      @_thats = {} # %Previous reply structure
      @_sorted = {} # Sorted buffers

      # "Current transaction" variables.
      @_current_user = `undefined` # Current user ID

      # Given any options?
      if typeof (opts) is "object"
        @_debug = (if opts["debug"] then true else false)  if opts["debug"]
        @_strict = (if opts["strict"] then true else false)  if opts["strict"]
        @_depth = parseInt(opts["depth"])  if opts["depth"]
        if opts["debug_div"]
          @_div = opts["debug_div"]
          @_div = "#" + @_div  unless @_div.indexOf("#") is 0

      # Set the default JavaScript language handler.
      @_handlers["javascript"] = new JsRiveObjects(this)
      @say "RiveScript Interpreter v" + VERSION + " Initialized."
      @say "Runtime Environment: " + @_runtime



  load: (name, code) ->
    source = "this._objects[\"" + name + "\"] = function (rs, args) {\n" + code.join("\n") + "}\n"
    try
      eval source
    catch e
      @_master.warn "Error evaluating JavaScript object: " + e.message
    return

  call: (rs, name, fields, scope) ->
    func = @_objects[name]
    reply = ""
    try
      reply = func.call(scope, rs, fields)
    catch e
      reply = "[ERR: Error when executing JavaScript object]"
    reply = ""  unless reply?
    reply

  VERSION = "1.03"
  RS_VERSION = "2.0"


  version = ->
    VERSION


  ###*
  private void runtime ()

  Detect the runtime environment of this module, to determine if we're
  running in a web browser or from NodeJS for example.
  ###
  runtime = ->

    # Make sure we have access to Object.keys().
    @_shim_keys()  unless Object.keys

    # In Node, there is no window, and module is a thing.
    if typeof (window) is "undefined" and typeof (module) is "object"
      @_node["fs"] = require("fs")
      "node"
    else
      "web"


  ###*
  private void say (string message)

  This is the debug function. If debug mode is enabled, the 'message' will be
  sent to the console via console.log (if available), or to your debug div if
  you defined one.

  @param message: A message to add to the debug log.
  ###
  RiveScript::say = (message) ->
    return  unless @_debug is true

    # A debug div provided?
    if @_div
      $(@_div).append "<div>[RS] " + @_escape_html(message) + "</div>"
    else console.log "[RS] " + message  if console and console.log
    return


  ###*
  private void warn (string message)

  Print a warning or error message. This is like debug, except it's GOING to be
  given to the user one way or another. If the debug div is defined, this is
  written to it. If console is defined, the error will be sent there. In a
  worst case scenario, an alert box is shown.
  ###
  RiveScript::warn = (message, fname, lineno) ->

    # Provided a file and line?
    message += " at " + fname + " line " + lineno  if typeof (fname) isnt "undefined" and typeof (lineno) isnt "undefined"
    if @_div

      # A debug div is provided.
      $(@_div).append "<div style='color: #FF0000; font-weight: bold'>" + @_escape_html(message) + "</div>"
    else if console

      # The console seems to exist.
      if console.error
        console.error message
      else console.log "[WARNING] " + message  if console.log
    else

      # Do the alert box.
      window.alert message
    return


  #//////////////////////////////////////////////////////////////////////////
  # Loading and Parsing Methods                                            //
  #//////////////////////////////////////////////////////////////////////////

  ###*
  int loadFile (string path || array path[, on_success[, on_error]])

  Load a RiveScript document from a file. The path can either be a string
  that contains the path to a single file, or an array of paths to load
  multiple files. on_success is a function to be called when the file(s)
  have been successfully loaded. on_error is for catching any errors, such
  as syntax errors.

  This loading method is asyncronous. You should define an on_success
  handler to be called when the file(s) have been successfully loaded.

  This method returns the "batch number" for this load attempt. The first
  call to this function will have a batch number of 0 and that will go
  up from there. This batch number is passed to your on_success handler
  as its only argument, in case you want to correlate it with your call
  to loadFile.

  on_success receives: int batch_count
  on_error receives: string error_message
  ###
  RiveScript::loadFile = (path, on_success, on_error) ->

    # Did they give us a single path?
    path = [path]  if typeof (path) is "string"

    # To identify when THIS batch of files completes, we keep track of them
    # under the "loadcount".
    loadcount = @_loadcount++
    @_pending[loadcount] = {}

    # Go through and load the files.
    i = 0

    while i < path.length
      file = path[i]
      @say "Request to load file: " + file
      @_pending[loadcount][file] = 1

      # How do we load the file?
      if @_runtime is "web"

        # With ajax!
        @_ajax_load_file loadcount, file, on_success, on_error

        # With Node FS!
      else @_node_load_file loadcount, file, on_success, on_error  if @_runtime is "node"
      i++
    loadcount


  # Load a file using ajax. DO NOT CALL THIS DIRECTLY.
  RiveScript::_ajax_load_file = (loadcount, file, on_success, on_error) ->

    # A pointer to ourself.
    RS = this

    # Make the Ajax request.


    $.ajax
      url: file
      dataType: "text"
      success: (data, textStatus, xhr) ->
        RS.say "Loading file " + file + " complete."

        # Parse it real good!
        RS.parse file, data, on_error

        # Log that we've received this file.
        delete RS._pending[loadcount][file]


        # All gone?
        on_success.call `undefined`, loadcount  if typeof (on_success) is "function"  if Object.keys(RS._pending[loadcount]).length is 0
        return

      error: (xhr, textStatus, errorThrown) ->
        RS.say "Error! " + textStatus + "; " + errorThrown
        on_error.call `undefined`, loadcount, textStatus  if typeof (on_error) is "function"
        return

    return


  # Load a file using Node FS. DO NOT CALL THIS DIRECTLY.


  RiveScript::_node_load_file = (loadcount, file, on_success, on_error) ->

    # A pointer to ourself.
    RS = this

    # Load the file.
    @_node.fs.readFile file, (err, data) ->
      if err
        if typeof (on_error) is "function"
          on_error.call `undefined`, loadcount, err
        else
          RS.warn err
        return

      # Parse it!
      RS.parse file, "" + data, on_error

      # Log that we've received this file.
      delete RS._pending[loadcount][file]


      # All gone?
      on_success.call `undefined`, loadcount  if typeof (on_success) is "function"  if Object.keys(RS._pending[loadcount]).length is 0
      return

    return


  ###*
  void loadDirectory (string path[, func on_success[, func on_error]])

  Load RiveScript documents from a directory.

  This function is not supported in a web environment. Only for
  NodeJS.
  ###
  RiveScript::loadDirectory = (path, on_success, on_error) ->

    # This can't be done on the web.
    if @_runtime is "web"
      @warn "loadDirectory can't be used on the web!"
      return
    loadcount = @_loadcount++
    @_pending[loadcount] = {}
    RS = this
    @_node.fs.readdir path, (err, files) ->
      if err
        if typeof (on_error) is "function"
          on_error.call `undefined`, err
        else
          RS.warn error
        return
      to_load = []
      i = 0
      iend = files.length

      while i < iend
        if files[i].match(/\.(rive|rs)$/i)

          # Keep track of the file's status.
          RS._pending[loadcount][path + "/" + files[i]] = 1
          to_load.push path + "/" + files[i]
        i++
      i = 0
      iend = to_load.length

      while i < iend
        file = to_load[i]

        # Load it.
        RS._node_load_file loadcount, to_load[i], on_success, on_error
        i++
      return

    return


  ###*
  bool stream (string code[, func on_error])

  Stream in RiveScript code dynamically. 'code' should be the raw
  RiveScript source code as a string (with line breaks after each line).

  This function is synchronous, meaning there is no success handler
  needed. It will return false on parsing error, true otherwise.

  on_error receives: string error_message
  ###
  RiveScript::stream = (code, on_error) ->
    @say "Streaming code."
    @parse "stream()", code, on_error


  ###*
  private bool parse (string name, string code[, func on_error])

  Parse RiveScript code and load it into memory. 'name' is a file name in
  case syntax errors need to be pointed out. 'code' is the source code,
  and 'on_error' is a function to call when a syntax error occurs.
  ###
  RiveScript::parse = (fname, code, on_error) ->
    @say "Parsing code!"

    # Track temporary variables.
    topic = "random" # Default topic=random
    lineno = 0 # Line numbers for syntax tracking
    comment = false # In a multi-line comment
    inobj = false # In an object
    objname = "" # The name of the object we're in
    objlang = "" # The programming language of the object
    objbuf = [] # Object contents buffer
    ontrig = "" # The current trigger
    repcnt = 0 # The reply counter
    concnt = 0 # The condition counter
    lastcmd = "" # Last command code
    isThat = "" # Is a %Previous trigger

    # Go through the lines of code.
    lines = code.split("\n")
    lp = 0
    ll = lines.length

    while lp < ll
      line = lines[lp]
      lineno = lp + 1

      # Strip the line.
      line = @_strip(line)
      continue  if line.length is 0 # Skip blank ones!

      # In an object?
      if inobj

        # End of the object?
        if line.indexOf("< object") > -1

          # End the object.
          if objname.length > 0

            # Call the object's handler.
            if @_handlers[objlang]
              @_objlangs[objname] = objlang
              @_handlers[objlang].load objname, objbuf
            else
              @warn "Object creation failed: no handler for " + objlang, fname, lineno
          objname = ""
          objlang = ""
          objbuf = ""
          inobj = false
        else
          objbuf.push line
        continue

      # Look for comments.
      if line.indexOf("//") is 0

        # Single line comments.
        continue
      else if line.indexOf("#") is 0

        # Old style single line comments.
        @warn "Using the # symbol for comments is deprecated", fname, lineno
        continue
      else if line.indexOf("/*") is 0

        # Start of a multi-line comment.

        # The end comment is on the same line!
        continue  if line.indexOf("*/") > -1

        # In a multi-line comment.
        comment = true
        continue
      else if line.indexOf("*/") > -1

        # End of a multi-line comment.
        comment = false
        continue
      continue  if comment

      # Separate the command from the data.
      if line.length < 2
        @warn "Weird single-character line '" + line + "' found", fname, lineno
        continue
      cmd = line.substring(0, 1)
      line = @_strip(line.substring(1))

      # Ignore in-line comments if there's a space before and after the "//" symbols.
      line = @_strip(line.split(" // ")[0])  if line.indexOf(" // ") > -1

      # Run a syntax check on this line.
      syntax_error = @checkSyntax(cmd, line)
      unless syntax_error is ""
        if @_strict and typeof (on_error) is "function"
          on_error.call null, "Syntax error: " + syntax_error + " at " + fname + " line " + lineno + ", near " + cmd + " " + line
          return false
        else
          @warn "Syntax error: " + syntax_error

      # Reset the %Previous state if this is a new +Trigger.
      isThat = ""  if cmd is "+"

      # Do a lookahead for ^Continue and %Previous commands.
      i = lp + 1

      while i < ll
        lookahead = @_strip(lines[i])
        continue  if lookahead.length < 2
        lookCmd = lookahead.substring(0, 1)
        lookahead = @_strip(lookahead.substring(1))

        # Only continue if the lookahead line has any data.
        unless lookahead.length is 0

          # The lookahead command has to be either a % or a ^.
          break  if lookCmd isnt "^" and lookCmd isnt "%"

          # If the current command is a +, see if the following is a %.
          if cmd is "+"
            if lookCmd is "%"
              isThat = lookahead
              break
            else
              isThat = ""

          # If the current command is a ! and the next command(s) are
          # ^, we'll tack each extension on as a line break (which is
          # useful information for arrays).
          if cmd is "!"
            line += "<crlf>" + lookahead  if lookCmd is "^"
            continue

          # If the current command is not a ^, and the line after is
          # not a %, but the line after IS a ^, then tack it on to the
          # end of the current line.
          if cmd isnt "^" and lookCmd isnt "%"
            if lookCmd is "^"
              line += lookahead
            else
              break
        i++
      @say "Cmd: '" + cmd + "'; line: " + line

      # Handle the types of RS commands.
      switch cmd
        when "!" # ! DEFINE
          halves = line.split("=", 2)
          left = @_strip(halves[0]).split(" ", 2)
          value = type = name = ""
          value = @_strip(halves[1])  if halves.length is 2
          if left.length >= 1
            type = @_strip(left[0])
            if left.length >= 2
              left.shift()
              name = @_strip(left.join(" "))

          # Remove 'fake' line breaks unless this is an array.
          value = value.replace(/<crlf>/g, "")  unless type is "array"

          # Handle version numbers.
          if type is "version"

            # Verify we support it.
            if parseFloat(value) > parseFloat(RS_VERSION)
              @warn "Unsupported RiveScript version. We only support " + RS_VERSION, fname, lineno
              return false
            continue

          # All other types of defines require a value and variable name.
          if name.length is 0
            @warn "Undefined variable name", fname, lineno
            continue
          else if value.length is 0
            @warn "Undefined variable value", fname, lineno
            continue

          # Handle the rest of the types.
          if type is "global"

            # 'Global' variables.
            @say "Set global " + name + " = " + value
            if value is "<undef>"
              delete @_gvars[name]

              continue
            else
              @_gvars[name] = value

            # Handle flipping debug and depth vars.
            if name is "debug"
              if value.toLowerCase() is "true"
                @_debug = true
              else
                @_debug = false
            else if name is "depth"
              @_depth = parseInt(value)
            else if name is "strict"
              if value.toLowerCase() is "true"
                @_strict = true
              else
                @_strict = false
          else if type is "var"

            # Bot variables.
            @say "Set bot variable " + name + " = " + value
            if value is "<undef>"
              delete @_bvars[name]
            else
              @_bvars[name] = value
          else if type is "array"

            # Arrays
            @say "Set array " + name + " = " + value
            if value is "<undef>"
              delete @_arrays[name]

              continue

            # Did this have multiple parts?
            parts = value.split("<crlf>")

            # Process each line of array data.
            fields = []
            i = 0
            end = parts.length

            while i < end
              val = parts[i]
              if val.indexOf("|") > -1
                tmp = val.split("|")
                fields.push.apply fields, val.split("|")
              else
                fields.push.apply fields, val.split(" ")
              i++

            # Convert any remaining '\s' over.
            i = 0
            end = fields.length

            while i < end
              fields[i] = fields[i].replace(/\\s/g, " ")
              i++
            @_arrays[name] = fields
          else if type is "sub"

            # Substitutions
            @say "Set substitution " + name + " = " + value
            if value is "<undef>"
              delete @_subs[name]
            else
              @_subs[name] = value
          else if type is "person"

            # Person substitutions
            @say "Set person substitution " + name + " = " + value
            if value is "<undef>"
              delete @_person[name]
            else
              @_person[name] = value
          else
            @warn "Unknown definition type '" + type + "'", fname, lineno
          continue
        when ">"

        # > LABEL
          temp = @_strip(line).split(" ")
          type = temp.shift()
          @say "line: " + line + "; temp: " + temp + "; type: " + type
          name = ""
          fields = []
          name = temp.shift()  if temp.length > 0
          fields = temp  if temp.length > 0

          # Handle the label types.
          if type is "begin"

            # The BEGIN block.
            @say "Found the BEGIN block."
            type = "topic"
            name = "__begin__"
          if type is "topic"

            # Starting a new topic.
            @say "Set topic to " + name
            ontrig = ""
            topic = name

            # Does this topic include or inherit another one?
            mode = "" # or 'inherits' or 'includes'
            if fields.length >= 2
              i = 0

              while i < fields.length
                field = fields[i]
                if field is "includes" or field is "inherits"
                  mode = field
                else unless mode is ""

                  # This topic is either inherited or included.
                  if mode is "includes"
                    @_includes[name] = {}  unless @_includes[name]
                    @_includes[name][field] = 1
                  else
                    @_lineage[name] = {}  unless @_lineage[name]
                    @_lineage[name][field] = 1
                i++
          else if type is "object"

            # If a field was provided, it should be the programming language.
            lang = `undefined`
            lang = fields[0].toLowerCase()  if fields.length > 0

            # Only try to parse a language we support.
            ontrig = ""
            unless lang?
              self.warn "Trying to parse unknown programming language", fname, lineno
              lang = "javascript" # Assume it's JS

            # See if we have a handler for this language.
            if @_handlers[lang]

              # We have a handler, so start loading the code.
              objname = name
              objlang = lang
              objbuf = []
              inobj = true
            else

              # We don't have a handler, so just ignore it.
              objname = ""
              objlang = ""
              objbuf = []
              inobj = true
          else
            @warn "Unknown label type '" + type + "'", fname, lineno
          continue
        when "<"

        # < LABEL
          type = line
          if type is "begin" or type is "topic"
            @say "End the topic label."
            topic = "random"
          else if type is "object"
            @say "End the object label."
            inobj = false
          continue
        when "+"

        # + TRIGGER
          @say "Trigger pattern: " + line
          if isThat.length > 0
            @_initTT "thats", topic, isThat, line
          else
            @_initTT "topics", topic, line
          ontrig = line
          repcnt = 0
          concnt = 0
          continue
        when "-"

        # - REPLY
          if ontrig is ""
            @warn "Response found before trigger", fname, lineno
            continue
          @say "Response: " + line
          if isThat.length > 0
            @_thats[topic][isThat][ontrig]["reply"][repcnt] = line
          else
            @_topics[topic][ontrig]["reply"][repcnt] = line
          repcnt++
          continue
        when "%"

        # % PREVIOUS
          continue # This was handled above.
        when "^"

        # ^ CONTINUE
          continue # This was handled above.
        when "@"

        # @ REDIRECT
          @say "Redirect response to: " + line
          if isThat.length > 0
            @_thats[topic][isThat][ontrig]["redirect"] = @_strip(line)
          else
            @_topics[topic][ontrig]["redirect"] = @_strip(line)
          continue
        when "*"

        # * CONDITION
          @say "Adding condition: " + line
          if isThat.length > 0
            @_thats[topic][isThat][ontrig]["condition"][concnt] = line
          else
            @_topics[topic][ontrig]["condition"][concnt] = line
          concnt++
          continue
        else
          @warn "Unknown command '" + cmd + "'", fname, lineno
      lp++
    true


  ###*
  string checkSyntax (char command, string line)

  Check the syntax of a RiveScript command. 'command' is the single
  character command symbol, and 'line' is the rest of the line after
  the command.

  Returns an empty string on success, or a description of the error
  on error.
  ###
  RiveScript::checkSyntax = (cmd, line) ->

    # Run syntax tests based on the command used.
    if cmd is "!"

      # ! Definition
      # - Must be formatted like this:
      #   ! type name = value
      #   OR
      #   ! type = value
      match = line.match(/^.+(?:\s+.+|)\s*=\s*.+?$/)
      return "Invalid format for !Definition line: must be '! type name = value' OR '! type = value'"  unless match
    else if cmd is ">"

      # > Label
      # - The "begin" label must have only one argument ("begin")
      # - The "topic" label must be lowercased but can inherit other topics (a-z0-9_\s)
      # - The "object" label must follow the same rules as "topic", but don't need to be lowercase.
      parts = line.split(/\s+/)
      if parts[0] is "begin" and parts.length > 1
        return "The 'begin' label takes no additional arguments."
      else if parts[0] is "topic"
        match = line.match(/[^a-z0-9_\-\s]/)
        return "Topics should be lowercased and contain only letters and numbers."  if match
      else if parts[0] is "object"
        match = line.match(/[^A-Za-z0-9\_\-\s]/)
        return "Objects can only contain numbers and letters."  if match
    else if cmd is "+" or cmd is "%" or cmd is "@"

      # + Trigger, % Previous, @ Redirect
      # This one is strict. The triggers are to be run through the regexp engine,
      # therefore it should be acceptable for the regexp engine.
      # - Entirely lowercase
      # - No symbols except: ( | ) [ ] * _ # @ { } < > =
      # - All brackets should be matched.
      parens = square = curly = angle = 0 # Count the brackets

      # Look for obvious errors first.
      return "Triggers may only contain lowercase letters, numbers, and these symbols: ( | ) [ ] * _ # @ { } < > ="  if line.match(/[^a-z0-9(|)\[\]*_#@{}<>=\s]/)

      # Count brackets.
      chars = line.split("")
      i = 0
      end = chars.length

      while i < end
        switch chars[i]
          when "("
            parens++
            continue
          when ")"
            parens--
            continue
          when "["
            square++
            continue
          when "]"
            square--
            continue
          when "{"
            curly++
            continue
          when "}"
            curly--
            continue
          when "<"
            angle++
            continue
          when ">"
            angle--
            continue
        i++

      # Any mismatches?
      unless parens is 0
        return "Unmatched parenthesis brackets."
      else unless square is 0
        return "Unmatched square brackets."
      else unless curly is 0
        return "Unmatched curly brackets."
      else return "Unmatched angle brackets."  unless angle is 0
    else if cmd is "*"

      # * Condition
      # Syntax for a conditional is as follows:
      # * value symbol value => response
      match = line.match(/^.+?\s*(?:==|eq|!=|ne|<>|<|<=|>|>=)\s*.+?=>.+?$/)
      return "Invalid format for !Condition: should be like '* value symbol value => response'"  unless match

    # No problems!
    ""


  # Initialize a Topic Tree data structure.
  RiveScript::_initTT = (toplevel, topic, trigger, what) ->
    if toplevel is "topics"
      @_topics[topic] = {}  unless @_topics[topic]
      unless @_topics[topic][trigger]
        @_topics[topic][trigger] =
          reply: {}
          condition: {}
          redirect: `undefined`
    else if toplevel is "thats"
      @_thats[topic] = {}  unless @_thats[topic]
      @_thats[topic][trigger] = {}  unless @_thats[topic][trigger]
      unless @_thats[topic][trigger][what]
        @_thats[topic][trigger][what] =
          reply: {}
          condition: {}
          redirect: `undefined`
    return


  #//////////////////////////////////////////////////////////////////////////
  # Loading and Parsing Methods                                            //
  #//////////////////////////////////////////////////////////////////////////

  ###*
  void sortReplies ()

  After you have finished loading your RiveScript code, call this method to
  populate the various sort buffers. This is absolutely necessary for
  reply matching to work efficiently!
  ###
  RiveScript::sortReplies = (thats) ->

    # This method can sort both triggers and that's.
    triglvl = undefined
    sortlvl = undefined
    if thats?
      triglvl = @_thats
      sortlvl = "thats"
    else
      triglvl = @_topics
      sortlvl = "topics"

    # (Re)initialize the sort cache.
    @_sorted[sortlvl] = {}
    @say "Sorting triggers..."

    # Loop through all the topics.
    for topic of triglvl
      @say "Analyzing topic " + topic

      # Collect a list of all the triggers we're going to worry about.
      # If this topic inherits another topic, we need to recursively add
      # those to the list as well.
      alltrig = @_topic_triggers(topic, triglvl)

      # Keep in mind here that there is a difference between 'includes'
      # and 'inherits' -- topics that inherit other topics are able to
      # OVERRIDE triggers that appear in the inherited topic. This means
      # that if the top topic has a trigger of simply '*', then NO
      # triggers are capable of matching in ANY inherited topic, because
      # even though * has the lowest priority, it has an automatic
      # priority over all inherited topics.
      #
      # The _topic_triggers method takes this into account. All topics
      # that inherit other topics will have their triggers prefixed with
      # a fictional {inherits} tag, which would start at {inherits=0} and
      # increment if the topic tree has other inheriting topics. So we can
      # use this tag to make sure topics that inherit things will have their
      # triggers always be on top of the stack, from inherits=0 to
      # inherits=n.

      # Sort these triggers.
      running = @_sort_trigger_set(alltrig)

      # Save this topic's sorted list.
      @_sorted[sortlvl] = {}  unless @_sorted[sortlvl]
      @_sorted[sortlvl][topic] = running

    # And do it all again for %Previous!
    unless thats?

      # This will set the %Previous lines to best match the bot's last reply.
      @sortReplies true

      # If any of the %Previous's had more than one +Trigger for them,
      # this will sort all those +Triggers to pair back to the best human
      # interaction.
      @_sort_that_triggers()

      # Also sort both kinds of substitutions.
      @_sort_list "subs", Object.keys(@_subs)
      @_sort_list "person", Object.keys(@_person)
    return


  # Make a list of sorted triggers that correspond to %Previous groups.
  RiveScript::_sort_that_triggers = ->
    @say "Sorting reverse triggers for %Previous groups..."

    # (Re)initialize the sort buffer.
    @_sorted["that_trig"] = {}
    for topic of @_thats
      @_sorted["that_trig"][topic] = {}  unless @_sorted["that_trig"][topic]
      for bottrig of @_thats[topic]
        @_sorted["that_trig"][topic][bottrig] = []  unless @_sorted["that_trig"][topic][bottrig]
        triggers = @_sort_trigger_set(Object.keys(@_thats[topic][bottrig]))
        @_sorted["that_trig"][topic][bottrig] = triggers
    return


  # Sort a group of triggers in an optimal sorting order.
  RiveScript::_sort_trigger_set = (triggers) ->

    # Create a priority map.
    prior =
      0: [] # Default priority = 0

    # Sort triggers by their weights.
    i = 0
    end = triggers.length

    while i < end
      trig = triggers[i]
      match = trig.match(/\{weight=(\d+)\}/i)
      weight = 0
      weight = match[1]  if match and match[1]
      prior[weight] = []  unless prior[weight]
      prior[weight].push trig
      i++

    # Keep a running list of sorted triggers for this topic.
    running = []

    # Sort them by priority.
    prior_sort = Object.keys(prior).sort((a, b) ->
      b - a
    )
    i = 0
    end = prior_sort.length

    while i < end
      p = prior_sort[i]
      @say "Sorting triggers with priority " + p

      # So, some of these triggers may include {inherits} tags, if they
      # came from a topic which inherits another topic. Lower inherits
      # values mean higher priority on the stack.
      inherits = -1 # -1 means no {inherits} tag
      highest_inherits = -1 # highest number seen so far

      # Loop through and categorize these triggers.
      track = {}
      track[inherits] = @_init_sort_track()
      j = 0
      jend = prior[p].length

      while j < jend
        trig = prior[p][j]
        @say "Looking at trigger: " + trig

        # See if it has an inherits tag.
        match = trig.match(/\{inherits=(\d+)\}/i)
        if match and match[1]
          inherits = parseInt(match[1])
          highest_inherits = inherits  if inherits > highest_inherits
          @say "Trigger belongs to a topic that inherits other topics. Level=" + inherits
          trig = trig.replace(/\{inherits=\d+\}/g, "")
        else
          inherits = -1

        # If this is the first time we've seen this inheritence level,
        # initialize its track structure.
        track[inherits] = @_init_sort_track()  unless track[inherits]

        # Start inspecting the trigger's contents.
        if trig.indexOf("_") > -1

          # Alphabetic wildcard included.
          cnt = @_word_count(trig)
          @say "Has a _ wildcard with " + cnt + " words."
          if cnt > 1
            track[inherits]["alpha"][cnt] = []  unless track[inherits]["alpha"][cnt]
            track[inherits]["alpha"][cnt].push trig
          else
            track[inherits]["under"].push trig
        else if trig.indexOf("#") > -1

          # Numeric wildcard included.
          cnt = @_word_count(trig)
          @say "Has a # wildcard with " + cnt + " words."
          if cnt > 1
            track[inherits]["number"][cnt] = []  unless track[inherits]["number"][cnt]
            track[inherits]["number"][cnt].push trig
          else
            track[inherits]["pound"].push trig
        else if trig.indexOf("*") > -1

          # Wildcard included.
          cnt = @_word_count(trig)
          @say "Has a * wildcard with " + cnt + " words."
          if cnt > 1
            track[inherits]["wild"][cnt] = []  unless track[inherits]["wild"][cnt]
            track[inherits]["wild"][cnt].push trig
          else
            track[inherits]["star"].push trig
        else if trig.indexOf("[") > -1

          # Optionals included.
          cnt = @_word_count(trig)
          @say "Has optionals with " + cnt + " words."
          track[inherits]["option"][cnt] = []  unless track[inherits]["option"][cnt]
          track[inherits]["option"][cnt].push trig
        else

          # Totally atomic.
          cnt = @_word_count(trig)
          @say "Totally atomic trigger and " + cnt + " words."
          track[inherits]["atomic"][cnt] = []  unless track[inherits]["atomic"][cnt]
          track[inherits]["atomic"][cnt].push trig
        j++

      # Move the no-{inherits} triggers to the bottom of the stack.
      track[(highest_inherits + 1)] = track["-1"]
      delete track["-1"]


      # Add this group to the sort list.
      track_sorted = Object.keys(track).sort((a, b) ->
        a - b
      )
      j = 0
      jend = track_sorted.length

      while j < jend
        ip = track_sorted[j]
        @say "ip=" + ip
        kinds = [
          "atomic"
          "option"
          "alpha"
          "number"
          "wild"
        ]
        k = 0
        kend = kinds.length

        while k < kend
          kind = kinds[k]
          kind_sorted = Object.keys(track[ip][kind]).sort((a, b) ->
            b - a
          )
          l = 0
          lend = kind_sorted.length

          while l < lend
            item = kind_sorted[l]
            running.push.apply running, track[ip][kind][item]
            l++
          k++
        under_sorted = track[ip]["under"].sort((a, b) ->
          b.length - a.length
        )
        pound_sorted = track[ip]["pound"].sort((a, b) ->
          b.length - a.length
        )
        star_sorted = track[ip]["star"].sort((a, b) ->
          b.length - a.length
        )
        running.push.apply running, under_sorted
        running.push.apply running, pound_sorted
        running.push.apply running, star_sorted
        j++
      i++
    running


  # Sort a simple list by number of words and length.
  RiveScript::_sort_list = (name, items) ->

    # Initialize the sort buffer.
    @_sorted["lists"] = {}  unless @_sorted["lists"]
    @_sorted["lists"][name] = []

    # Track by number of words.
    track = {}

    # Loop through each item.
    i = 0
    end = items.length

    while i < end

      # Count the words.
      cnt = @_word_count(items[i], true)
      track[cnt] = []  unless track[cnt]
      track[cnt].push items[i]
      i++

    # Sort them.
    output = []
    sorted = Object.keys(track).sort((a, b) ->
      b - a
    )
    i = 0
    end = sorted.length

    while i < end
      count = sorted[i]
      bylen = track[count].sort((a, b) ->
        b.length - a.length
      )
      output.push.apply output, bylen
      i++
    @_sorted["lists"][name] = output
    return


  # Returns a new hash for keeping track of triggers for sorting.
  RiveScript::_init_sort_track = ->
    atomic: {} # Sort by number of whole words
    option: {} # Sort optionals by number of words
    alpha: {} # Sort alpha wildcards by no. of words
    number: {} # Sort number wildcards by no. of words
    wild: {} # Sort wildcards by no. of words
    pound: [] # Triggers of just #
    under: [] # Triggers of just _
    star: [] # Triggers of just *


  #//////////////////////////////////////////////////////////////////////////
  # Public Configuration Methods                                           //
  #//////////////////////////////////////////////////////////////////////////

  ###*
  void setHandler (string lang, object)

  Set a custom language handler for RiveScript objects. See the source for
  the built-in JavaScript handler as an example.

  @param lang: The lowercased name of the programming language, e.g. perl, python
  @param obj:  A JavaScript object that has functions named "load" and "call".
  Use the undefined value to delete a language handler.
  ###
  RiveScript::setHandler = (lang, obj) ->
    unless obj?
      delete @_handlers[lang]
    else
      @_handlers[lang] = obj
    return


  ###*
  void setSubroutine (string name, function)

  Define a JavaScript object from your program.

  This is equivalent to having a JS object defined in the RiveScript code, except
  your JavaScript code is defining it instead.
  ###
  RiveScript::setSubroutine = (name, code) ->

    # Do we have a JS handler?
    if @_handlers["javascript"]
      @_handlers["javascript"]._objects[name] = code
    else
      @warn "Can't setSubroutine: no JavaScript object handler is loaded!"
    return


  ###*
  void setGlobal (string name, string value)

  Set a global variable. This is equivalent to '! global' in RiveScript.
  Set the value to undefined to delete a global.
  ###
  RiveScript::setGlobal = (name, value) ->
    unless value?
      delete @_gvars[name]
    else
      @_gvars[name] = value
    return


  ###*
  void setVariable (string name, string value)

  Set a bot variable. This is equivalent to '! var' in RiveScript.
  Set the value to undefined to delete a variable.
  ###
  RiveScript::setVariable = (name, value) ->
    unless value?
      delete @_bvars[name]
    else
      @_bvars[name] = value
    return


  ###*
  void setSubstitution (string name, string value)

  Set a substitution. This is equivalent to '! sub' in RiveScript.
  Set the value to undefined to delete a substitution.
  ###
  RiveScript::setSubstitution = (name, value) ->
    unless value?
      delete @_subs[name]
    else
      @_subs[name] = value
    return


  ###*
  void setPerson (string name, string value)

  Set a person substitution. This is equivalent to '! person' in RiveScript.
  Set the value to undefined to delete a substitution.
  ###
  RiveScript::setPerson = (name, value) ->
    unless value?
      delete @_person[name]
    else
      @_person[name] = value
    return


  ###*
  void setUservar (string user, string name, string value)

  Set a user variable for a user.
  ###
  RiveScript::setUservar = (user, name, value) ->

    # Initialize the user?
    @_users[user] =
      topic: "random"  unless @_users[user]
    unless value?
      delete @_users[user][name]
    else
      @_users[user][name] = value
    return


  ###*
  string getUservar (string user, string name)

  Get a variable from a user. Returns the string "undefined" if it isn't
  defined.
  ###
  RiveScript::getUservar = (user, name) ->

    # No user?
    return "undefined"  unless @_users[user]

    # The var exists?
    if @_users[user][name]
      @_users[user][name]
    else
      "undefined"


  ###*
  data getUservars ([string user])

  Get all variables about a user. If no user is provided, returns all
  data about all users.
  ###
  RiveScript::getUservars = (user) ->
    unless user?

      # All the users! Return a cloned object to break refs.
      @_clone @_users
    else

      # Exists?
      if @_users[user]
        @_clone @_users[user]
      else
        `undefined`


  ###*
  void clearUservars ([string user])

  Clear all a user's variables. If no user is provided, clears all variables
  for all users.
  ###
  RiveScript::clearUservars = (user) ->
    unless user?

      # All the users!
      @_users = {}
    else
      delete @_users[user]
    return


  ###*
  void freezeUservars (string user)

  Freeze the variable state of a user. This will clone and preserve the user's
  entire variable state, so that it can be restored later with thawUservars().
  ###
  RiveScript::freezeUservars = (user) ->
    if @_users[user]

      # Freeze them.
      @_freeze[user] = @_clone(@_users[user])
    else
      @warn "Can't freeze vars for user " + user + ": not found!"
    return


  ###*
  void thawUservars (string user[, string action])

  Thaws a user's frozen variables. The action can be one of the following:
  - discard: Don't restore the variables, just delete the frozen copy.
  - keep:    Keep the frozen copy after restoring.
  - thaw:    Restore the variables and delete the frozen copy (default)
  ###
  RiveScript::thawUservars = (user, action) ->
    action = "thaw"  unless typeof (action) is "string"

    # Frozen?
    unless @_freeze[user]
      @warn "Can't thaw user vars: " + user + " not found!"
      return

    # What are we doing?
    if action is "thaw"

      # Thawing them out.
      @clearUservars user
      @_users[user] = @_clone(@_freeze[user])
      delete @_freeze[user]
    else if action is "discard"

      # Just throw it away.
      delete @_freeze[user]
    else if action is "keep"

      # Copy them back, but keep them.
      @clearUservars user
      @_users[user] = @_clone(@_freeze[user])
    else
      @warn "Unsupported thaw action"
    return


  ###*
  void lastMatch (string user)

  Retrieve the trigger that the user matched most recently.
  ###
  RiveScript::lastMatch = (user) ->
    return @_users[user]["__lastmatch__"]  if @_users[user]
    `undefined`


  ###*
  string currentUser ()

  Retrieve the current user's ID. This is most useful within a JavaScript
  object macro to get the ID of the user who invoked the macro (e.g. to
  get/set user variables for them).

  This will return undefined if called from outside of a reply context
  (the value is unset at the end of the reply() method).
  ###
  RiveScript::currentUser = ->
    @warn "currentUser() is intended to be called from within a JS object macro!"  unless @_current_user?
    @_current_user


  #//////////////////////////////////////////////////////////////////////////
  # Reply Fetching Methods                                                 //
  #//////////////////////////////////////////////////////////////////////////

  ###*
  string reply (string username, string message)

  Fetch a reply from the RiveScript brain. The message doesn't require any
  special pre-processing to be done to it, i.e. it's allowed to contain
  punctuation and weird symbols. The username is arbitrary and is used to
  uniquely identify the user, in the case that you may have multiple
  distinct users chatting with your bot.
  ###
  RiveScript::reply = (user, msg, scope) ->
    @say "Asked to reply to [" + user + "] " + msg

    # Store the current user's ID.
    @_current_user = user

    # Format their message.
    msg = @_format_message(msg)
    reply = ""

    # If the BEGIN block exists, consult it first.
    if @_topics["__begin__"]
      begin = @_getreply(user, "request", "begin", 0, scope)

      # Okay to continue?
      if begin.indexOf("{ok}") > -1
        reply = @_getreply(user, msg, "normal", 0, scope)
        begin = begin.replace(/\{ok\}/g, reply)
      reply = begin
      reply = @_process_tags(user, msg, reply, [], [], 0, scope)
    else
      reply = @_getreply(user, msg, "normal", 0, scope)

    # Save their reply history.
    @_users[user]["__history__"]["input"].pop()
    @_users[user]["__history__"]["input"].unshift msg
    @_users[user]["__history__"]["reply"].pop()
    @_users[user]["__history__"]["reply"].unshift reply

    # Unset the current user's ID.
    @_current_user = `undefined`
    reply


  # Format a user's message for safe processing.
  RiveScript::_format_message = (msg) ->

    # Lowercase it.
    msg = "" + msg
    msg = msg.toLowerCase()

    # Run substitutions and sanitize what's left.
    msg = @_substitute(msg, "subs")
    msg = @_strip_nasties(msg)
    msg


  # The internal reply method. DO NOT CALL THIS DIRECTLY.
  RiveScript::_getreply = (user, msg, context, step, scope) ->

    # Need to sort replies?
    unless @_sorted["topics"]
      @warn "You forgot to call sortReplies()!"
      return "ERR: Replies Not Sorted"

    # Initialize the user's profile?
    @_users[user] =
      topic: "random"  unless @_users[user]

    # Collect data on this user.
    topic = @_users[user]["topic"]
    stars = []
    thatstars = [] # For %Previous
    reply = ""

    # Avoid letting them fall into a missing topic.
    unless @_topics[topic]
      @warn "User " + user + " was in an empty topic named '" + topic + "'"
      topic = @_users[user]["topic"] = "random"

    # Avoid deep recursion.
    return "ERR: Deep Recursion Detected"  if step > @_depth

    # Are we in the BEGIN block?
    topic = "__begin__"  if context is "begin"

    # Initialize this user's history.
    unless @_users[user]["__history__"]
      @_users[user]["__history__"] =
        input: [
          "undefined"
          "undefined"
          "undefined"
          "undefined"
          "undefined"
          "undefined"
          "undefined"
          "undefined"
          "undefined"
          "undefined"
        ]
        reply: [
          "undefined"
          "undefined"
          "undefined"
          "undefined"
          "undefined"
          "undefined"
          "undefined"
          "undefined"
          "undefined"
          "undefined"
        ]

    # More topic sanity checking.

    # This was handled before, which would mean topic=random and it
    # doesn't exist. Serious issue!
    return "ERR: No default topic 'random' was found!"  unless @_topics[topic]

    # Create a pointer for the matched data when we find it.
    matched = null
    matchedTrigger = null
    foundMatch = false

    # See if there were any %Previous's in this topic, or any topic related
    # to it. This should only be done the first time -- not during a recursive
    # redirection. This is because in a redirection, "lastreply" is still gonna
    # be the same as it was the first time, resulting in an infinite loop!
    if step is 0
      allTopics = [topic]

      # Get ALL the topics!
      allTopics = @_get_topic_tree(topic)  if @_includes[topic] or @_lineage[topic]

      # Scan them all.
      i = 0
      iend = allTopics.length

      while i < iend
        top = allTopics[i]
        @say "Checking topic " + top + " for any %Previous's."
        if @_sorted["thats"][top]

          # There's one here!
          @say "There's a %Previous in this topic!"

          # Do we have history yet?
          lastReply = @_users[user]["__history__"]["reply"][0]

          # Format the bot's last reply the same way as the human's.
          lastReply = @_format_message(lastReply)
          @say "Last reply: " + lastReply

          # See if it's a match.
          j = 0
          jend = @_sorted["thats"][top].length

          while j < jend
            trig = @_sorted["thats"][top][j]
            botside = @_reply_regexp(user, trig)
            @say "Try to match lastReply (" + lastReply + ") to " + botside

            # Match?
            match = lastReply.match(new RegExp("^" + botside + "$"))
            if match

              # Huzzah! See if OUR message is right too.
              @say "Bot side matched!"
              thatstars = [] # Collect the bot stars in case we need them.
              k = 1
              kend = match.length

              while k < kend
                thatstars.push match[k]
                k++

              # Compare the triggers to the user's message.
              k = 0
              kend = @_sorted["that_trig"][top][trig].length

              while k < kend
                subtrig = @_sorted["that_trig"][top][trig][k]
                humanside = @_reply_regexp(user, subtrig)
                @say "Now try to match " + msg + " to " + humanside
                match = msg.match(new RegExp("^" + humanside + "$"))
                if match
                  @say "Found a match!"
                  matched = @_thats[top][trig][subtrig]
                  matchedTrigger = subtrig
                  foundMatch = true

                  # Collect the stars.
                  stars = []
                  if match.length > 1
                    j = 1
                    jend = match.length

                    while j < jend
                      stars.push match[j]
                      j++
                  break
                k++

            # Stop if we found a match.
            break  if foundMatch
            j++

        # Stop if we found a match.
        break  if foundMatch
        i++

    # Search their topic for a match to their trigger.
    unless foundMatch
      @say "Searching their topic for a match..."
      i = 0
      iend = @_sorted["topics"][topic].length

      while i < iend
        trig = @_sorted["topics"][topic][i]
        regexp = @_reply_regexp(user, trig)
        @say "Try to match \"" + msg + "\" against " + trig + " (" + regexp + ")"

        # If the trigger is atomic, we don't need to bother with the regexp engine.
        isAtomic = @_is_atomic(trig)
        isMatch = false
        if isAtomic
          isMatch = true  if msg is regexp
        else

          # Non-atomic triggers always need the regexp.
          match = msg.match(new RegExp("^" + regexp + "$"))
          if match

            # The regexp matched!
            isMatch = true

            # Collect the stars.
            stars = []
            if match.length > 1
              j = 1
              jend = match.length

              while j < jend
                stars.push match[j]
                j++

        # A match somehow?
        if isMatch
          @say "Found a match!"

          # We found a match, but what if the trigger we've matched
          # doesn't belong to our topic? Find it!
          unless @_topics[topic][trig]

            # We have to find it.
            matched = @_find_trigger_by_inheritence(topic, trig, 0)
          else
            matched = @_topics[topic][trig]
          foundMatch = true
          matchedTrigger = trig
          break
        i++

    # Store what trigger they matched on. If their matched trigger is undefined,
    # this will be too, which is great.
    @_users[user]["__lastmatch__"] = matchedTrigger

    # Did we match?
    if matched
      nil = 0

      while nil < 1

        # See if there are any hard redirects.
        if matched["redirect"]
          @say "Redirecting us to '" + matched["redirect"] + "'"
          redirect = @_process_tags(user, msg, matched["redirect"], stars, thatstars, step, scope)
          @say "Pretend user said: " + redirect
          reply = @_getreply(user, redirect, context, (step + 1), scope)
          break

        # Check the conditionals.
        i = 0

        while matched["condition"][i]
          halves = matched["condition"][i].split(/\s*=>\s*/)
          if halves and halves.length is 2
            condition = halves[0].match(/^(.+?)\s+(==|eq|!=|ne|<>|<|<=|>|>=)\s+(.+?)$/)
            if condition
              left = @_strip(condition[1])
              eq = condition[2]
              right = @_strip(condition[3])
              potreply = @_strip(halves[1])

              # Process tags all around.
              left = @_process_tags(user, msg, left, stars, thatstars, step, scope)
              right = @_process_tags(user, msg, right, stars, thatstars, step, scope)

              # Defaults?
              left = "undefined"  if left.length is 0
              right = "undefined"  if right.length is 0
              @say "Check if " + left + " " + eq + " " + right

              # Validate it.
              passed = false
              if eq is "eq" or eq is "=="
                passed = true  if left is right
              else if eq is "ne" or eq is "!=" or eq is "<>"
                passed = true  unless left is right
              else

                # Dealing with numbers here.
                try
                  left = parseInt(left)
                  right = parseInt(right)
                  if eq is "<"
                    passed = true  if left < right
                  else if eq is "<="
                    passed = true  if left <= right
                  else if eq is ">"
                    passed = true  if left > right
                  else passed = true  if left >= right  if eq is ">="
                catch e
                  @warn "Failed to evaluate numeric condition!"

              # OK?
              if passed
                reply = potreply
                break
          i++

        # Have our reply yet?
        break  if reply? and reply.length > 0

        # Process weights in the replies.
        bucket = []
        for rep_index of matched["reply"]
          rep = matched["reply"][rep_index]
          weight = 1
          match = rep.match(/\{weight=(\\d+?)\}/i)
          if match
            weight = match[1]
            if weight <= 0
              @warn "Can't have a weight <= 0!"
              weight = 1
          j = 0

          while j < weight
            bucket.push rep
            j++

        # Get a random reply.
        choice = parseInt(Math.random() * bucket.length)
        reply = bucket[choice]
        break
        nil++

    # Still no reply?
    unless foundMatch
      reply = "ERR: No Reply Matched"
    else reply = "ERR: No Reply Found"  if not reply? or reply.length is 0
    @say "Reply: " + reply

    # Process tags for the BEGIN block.
    if context is "begin"

      # The BEGIN block can set {topic} and user vars.
      giveup = 0

      # Topic setter.
      match = reply.match(/\{topic=(.+?)\}/i)
      while match
        giveup++
        if giveup >= 50
          @warn "Infinite loop looking for topic tag!"
          break
        name = match[1]
        @_users[user]["topic"] = name
        reply = reply.replace(new RegExp("{topic=" + @quotemeta(name) + "}", "ig"), "")
        match = reply.match(/\{topic=(.+?)\}/i) # Look for more

      # Set user vars.
      match = reply.match(/<set (.+?)=(.+?)>/i)
      giveup = 0
      while match
        giveup++
        if giveup >= 50
          @warn "Infinite loop looking for set tag!"
          break
        name = match[1]
        value = match[2]
        @_users[user][name] = value
    else

      # Process more tags if not in BEGIN.
      reply = @_process_tags(user, msg, reply, stars, thatstars, step, scope)
    reply


  # Prepares a trigger for the regular expression engine.
  RiveScript::_reply_regexp = (user, regexp) ->

    # If the trigger is simply '*' then the * needs to become (.*?)
    # to match the blank string too.
    regexp = regexp.replace(/^\*$/, "<zerowidthstar>")

    # Simple replacements.
    regexp = regexp.replace(/\*/g, "(.+?)") # Convert * into (.+?)
    regexp = regexp.replace(/#/g, "(\\d+?)") # Convert # into (\d+?)
      regexp = regexp.replace(/_/g, "([A-Za-z]+?)") # Convert _ into (\w+?)
        regexp = regexp.replace(/\{weight=\d+\}/g, "") # Remove {weight} tags
    regexp = regexp.replace(/<zerowidthstar>/g, "(.*?)")

    # Optionals.
    match = regexp.match(/\[(.+?)\]/)
    giveup = 0
    while match
      giveup++
      if giveup >= 50
        @warn "Infinite loop when trying to process optionals in trigger!"
        return ""
      parts = match[1].split("|")
      opts = []
      i = 0
      iend = parts.length

      while i < iend
        p = "\\s*" + parts[i] + "\\s*"
        opts.push p
        i++
      opts.push "\\s*"

      # If this optional had a star or anything in it, make it non-matching.
      pipes = opts.join("|")
      pipes = pipes.replace(new RegExp(@quotemeta("(.+?)"), "g"), "(?:.+?)")
      pipes = pipes.replace(new RegExp(@quotemeta("(\\d+?)"), "g"), "(?:\\d+?)")
      pipes = pipes.replace(new RegExp(@quotemeta("([A-Za-z]+?)"), "g"), "(?:[A-Za-z]+?)")
      regexp = regexp.replace(new RegExp("\\s*\\[" + @quotemeta(match[1]) + "\\]\\s*"), "(?:" + pipes + ")")
      match = regexp.match(/\[(.+?)\]/) # Circle of life!

    # Filter in arrays.
    giveup = 0
    while regexp.indexOf("@") > -1
      giveup++
      break  if giveup >= 50
      match = regexp.match(/\@(.+?)\b/)
      if match
        name = match[1]
        rep = ""
        rep = "(?:" + @_arrays[name].join("|") + ")"  if @_arrays[name]
        regexp = regexp.replace(new RegExp("@" + @quotemeta(name) + "\\b"), rep)

    # Filter in bot variables.
    giveup = 0
    while regexp.indexOf("<bot") > -1
      giveup++
      break  if giveup >= 50
      match = regexp.match(/<bot (.+?)>/i)
      if match
        name = match[1]
        rep = ""
        rep = @_strip_nasties(@_bvars[name])  if @_bvars[name]
        regexp = regexp.replace(new RegExp("<bot " + @quotemeta(name) + ">"), rep)

    # Filter in user variables.
    match = regexp.match(/<get (.+?)>/i)
    giveup = 0
    while match
      giveup++
      if giveup >= 50
        @warn "Infinite loop looking for get tag!"
        break
      name = match[1]
      value = "undefined"
      value = @_users[user][name]  if @_users[user][name]
      regexp = regexp.replace(new RegExp("<get " + @quotemeta(name) + ">", "ig"), value)
      match = regexp.match(/<get (.+?)>/i) # Look for more

    # Filter in <input> and <reply> tags.
    if regexp.indexOf("<input") > -1 or regexp.indexOf("<reply") > -1
      types = [
        "input"
        "reply"
      ]
      i = 0

      while i < 2
        type = types[i]
        j = 1

        while j <= 9
          regexp = regexp.replace(new RegExp("<" + type + j + ">", "g"),
            @_users[user]["__history__"][type][j])  if regexp.indexOf("<" + type + j + ">")
          j++
        regexp = regexp.replace(new RegExp("<" + type + ">", "g"), @_users[user]["__history__"][type][0])
        i++
    regexp


  # Process tags in a reply element.
  RiveScript::_process_tags = (user, msg, reply, st, bst, step, scope) ->

    # Prepare the stars and botstars.
    stars = [""]
    stars.push.apply stars, st
    botstars = [""]
    botstars.push.apply botstars, bst
    stars.push "undefined"  if stars.length is 1
    botstars.push "undefined"  if botstars.length is 1

    # For while loops.
    match = undefined
    giveup = 0

    # Tag shortcuts.
    reply = reply.replace(/<person>/g, "{person}<star>{/person}")
    reply = reply.replace(/<@>/g, "{@<star>}")
    reply = reply.replace(/<formal>/g, "{formal}<star>{/formal}")
    reply = reply.replace(/<sentence>/g, "{sentence}<star>{/sentence}")
    reply = reply.replace(/<uppercase>/g, "{uppercase}<star>{/uppercase}")
    reply = reply.replace(/<lowercase>/g, "{lowercase}<star>{/lowercase}")

    # Weight and star tags.
    reply = reply.replace(/\{weight=\d+\}/g, "") # Leftover {weight}s
    reply = reply.replace(/<star>/g, stars[1])
    reply = reply.replace(/<botstar>/g, botstars[1])
    i = 1

    while i <= stars.length
      reply = reply.replace(new RegExp("<star" + i + ">", "ig"), stars[i])
      i++
    i = 1

    while i <= botstars.length
      reply = reply.replace(new RegExp("<botstar" + i + ">", "ig"), botstars[i])
      i++

    # <input> and <reply>
    reply = reply.replace(/<input>/g, @_users[user]["__history__"]["input"][0])
    reply = reply.replace(/<reply>/g, @_users[user]["__history__"]["reply"][0])
    i = 1

    while i <= 9
      reply = reply.replace(new RegExp("<input" + i + ">", "ig"),
        @_users[user]["__history__"]["input"][i])  if reply.indexOf("<input" + i + ">")
      reply = reply.replace(new RegExp("<reply" + i + ">", "ig"),
        @_users[user]["__history__"]["reply"][i])  if reply.indexOf("<reply" + i + ">")
      i++

    # <id> and escape codes
    reply = reply.replace(/<id>/g, user)
    reply = reply.replace(/\\s/g, " ")
    reply = reply.replace(/\\n/g, "\n")
    reply = reply.replace(/\\#/g, "#")

    # {random}
    match = reply.match(/\{random\}(.+?)\{\/random\}/i)
    giveup = 0
    while match
      giveup++
      if giveup > 50
        @warn "Infinite loop looking for random tag!"
        break
      random = []
      text = match[1]
      if text.indexOf("|") > -1
        random = text.split("|")
      else
        random = text.split(" ")
      output = random[parseInt(Math.random() * random.length)]
      reply = reply.replace(new RegExp("\\{random\\}" + @quotemeta(text) + "\\{\\/random\\}", "ig"), output)
      match = reply.match(/\{random\}(.+?)\{\/random\}/i)

    # Person Substitutions & String formatting.
    formats = [
      "person"
      "formal"
      "sentence"
      "uppercase"
      "lowercase"
    ]
    i = 0

    while i < 5
      type = formats[i]
      match = reply.match(new RegExp("{" + type + "}(.+?){/" + type + "}", "i"))
      giveup = 0
      while match
        giveup++
        if giveup >= 50
          @warn "Infinite loop looking for " + type + " tag!"
          break
        content = match[1]
        replace = undefined
        if type is "person"
          replace = @_substitute(content, "person")
        else
          replace = @_string_format(type, content)
        reply = reply.replace(new RegExp("{" + type + "}" + @quotemeta(content) + "{/" + type + "}", "ig"), replace)
        match = reply.match(new RegExp("{" + type + "}(.+?){/" + type + "}", "i"))
      i++

    # Bot variables: set
    match = reply.match(/<bot ([^>]+?)=([^>]+?)>/i)
    giveup = 0
    while match
      giveup++
      if giveup >= 50
        @warn "Infinite loop looking for bot set tag!"
        break
      name = match[1]
      value = match[2]
      @_bvars[name] = value
      reply = reply.replace(new RegExp("<bot " + @quotemeta(name) + "=" + @quotemeta(value) + ">", "ig"), "")
      match = reply.match(/<bot ([^>]+?)=([^>]+?)>/i)

    # Bot variables: get
    match = reply.match(/<bot ([^>]+?)>/i)
    giveup = 0
    while match
      giveup++
      if giveup >= 50
        @warn "Infinite loop looking for bot tag!"
        break
      name = match[1]
      value = "undefined"
      value = @_bvars[name]  if @_bvars[name]
      reply = reply.replace(new RegExp("<bot " + @quotemeta(name) + ">", "ig"), value)
      match = reply.match(/<bot ([^>]+?)>/i) # Look for more

    # Global variables: set
    match = reply.match(/<env ([^>]+?)=([^>]+?)>/i)
    giveup = 0
    while match
      giveup++
      if giveup >= 50
        @warn "Infinite loop looking for env set tag!"
        break
      name = match[1]
      value = match[2]
      @_gvars[name] = value
      reply = reply.replace(new RegExp("<env " + @quotemeta(name) + "=" + @quotemeta(value) + ">", "ig"), "")
      match = reply.match(/<env ([^>]+?)=([^>]+?)>/i)

    # Global variables: get
    match = reply.match(/<env ([^>]+?)>/i)
    giveup = 0
    while match
      giveup++
      if giveup >= 50
        @warn "Infinite loop looking for env tag!"
        break
      name = match[1]
      value = "undefined"
      value = @_gvars[name]  if @_gvars[name]
      reply = reply.replace(new RegExp("<env " + @quotemeta(name) + ">", "ig"), value)
      match = reply.match(/<env ([^>]+?)>/i) # Look for more

    # Set user vars.
    match = reply.match(/<set ([^>]+?)=([^>]+?)>/i)
    giveup = 0
    while match
      giveup++
      if giveup >= 50
        @warn "Infinite loop looking for set tag!"
        break
      name = match[1]
      value = match[2]
      @_users[user][name] = value
      reply = reply.replace(new RegExp("<set " + @quotemeta(name) + "=" + @quotemeta(value) + ">", "ig"), "")
      match = reply.match(/<set ([^>]+?)=([^>]+?)>/i) # Look for more

    # Math tags.
    math = [
      "add"
      "sub"
      "mult"
      "div"
    ]
    i = 0

    while i < 4
      oper = math[i]
      match = reply.match(new RegExp("<" + oper + " ([^>]+?)=([^>]+?)>"))
      giveup = 0
      while match
        name = match[1]
        value = match[2]
        newval = 0
        output = ""

        # Sanity check.
        value = parseInt(value)
        if isNaN(value)
          output = "[ERR: Math can't '" + oper + "' non-numeric value '" + match[2] + "']"
        else if isNaN(parseInt(@_users[user][name]))
          output = "[ERR: Math can't '" + oper + "' non-numeric user variable '" + name + "']"
        else
          orig = parseInt(@_users[user][name])
          if oper is "add"
            newval = orig + value
          else if oper is "sub"
            newval = orig - value
          else if oper is "mult"
            newval = orig * value
          else if oper is "div"
            if value is 0
              output = "[ERR: Can't Divide By Zero]"
            else
              newval = orig / value

        # No errors?

        # Commit.
        @_users[user][name] = newval  if output is ""
        reply = reply.replace(new RegExp("<" + oper + " " + @quotemeta(name) + "=" + @quotemeta("" + value) + ">", "i"),
          output)
        match = reply.match(new RegExp("<" + oper + " ([^>]+?)=([^>]+?)>"))
      i++

    # Get user vars.
    match = reply.match(/<get (.+?)>/i)
    giveup = 0
    while match
      giveup++
      if giveup >= 50
        @warn "Infinite loop looking for get tag!"
        break
      name = match[1]
      value = "undefined"
      value = @_users[user][name]  if @_users[user][name]
      reply = reply.replace(new RegExp("<get " + @quotemeta(name) + ">", "ig"), value)
      match = reply.match(/<get (.+?)>/i) # Look for more

    # Topic setter.
    match = reply.match(/\{topic=(.+?)\}/i)
    giveup = 0
    while match
      giveup++
      if giveup >= 50
        @warn "Infinite loop looking for topic tag!"
        break
      name = match[1]
      @_users[user]["topic"] = name
      reply = reply.replace(new RegExp("{topic=" + @quotemeta(name) + "}", "ig"), "")
      match = reply.match(/\{topic=(.+?)\}/i) # Look for more

    # Inline redirector.
    match = reply.match(/\{@(.+?)\}/)
    giveup = 0
    while match
      giveup++
      if giveup >= 50
        @warn "Infinite loop looking for redirect tag!"
        break
      target = @_strip(match[1])
      @say "Inline redirection to: " + target
      subreply = @_getreply(user, target, "normal", step + 1, scope)
      reply = reply.replace(new RegExp("\\{@" + @quotemeta(target) + "\\}", "i"), subreply)
      match = reply.match(/\{@(.+?)\}/)

    # Object caller.
    match = reply.match(/<call>(.+?)<\/call>/i)
    giveup = 0
    while match
      giveup++
      if giveup >= 50
        @warn "Infinite loop looking for call tag!"
        break
      text = @_strip(match[1])
      parts = text.split(/\s+/)
      obj = parts[0]
      args = []
      i = 1
      iend = parts.length

      while i < iend
        args.push parts[i]
        i++

      # Do we know this object?
      output = ""
      if @_objlangs[obj]

        # We do. Do we have a handler for it?
        lang = @_objlangs[obj]
        if @_handlers[lang]

          # We do.
          output = @_handlers[lang].call(this, obj, args, scope)
        else
          output = "[ERR: No Object Handler]"
      else
        output = "[ERR: Object Not Found]"
      reply = reply.replace(new RegExp("<call>" + @quotemeta(match[1]) + "</call>", "i"), output)
      match = reply.match(/<call>(.+?)<\/call>/i)
    reply


  # Run a kind of substitution on a message.
  RiveScript::_substitute = (msg, list) ->

    # Safety checking.
    if not @_sorted["lists"] or not @_sorted["lists"][list]
      @warn "You forgot to call sortReplies()!"
      return ""

    # Get the substitutions map.
    subs = undefined
    if list is "subs"
      subs = @_subs
    else
      subs = @_person
    notword = "([^A-Za-z0-9])"
    notword = "(\\W+)"
    i = 0
    end = @_sorted["lists"][list].length

    while i < end
      pattern = @_sorted["lists"][list][i]
      result = "<rot13sub>" + @_rot13(subs[pattern]) + "<bus31tor>"
      qm = @quotemeta(pattern)

      # Run substitutions.
      msg = msg.replace(new RegExp("^" + qm + "$", "g"), result)
      msg = msg.replace(new RegExp("^" + qm + "(\\W+)", "g"), result + "$1")
      msg = msg.replace(new RegExp("(\\W+)" + qm + "(\\W+)", "g"), "$1" + result + "$2")
      msg = msg.replace(new RegExp("(\\W+)" + qm + "$", "g"), "$1" + result)
      i++

    # Convert the rot13-escaped placeholders back.
    tries = 0
    while msg.indexOf("<rot13sub>") > -1
      tries++
      if tries > 50
        @warn "Too many loops!"
        break
      match = msg.match("<rot13sub>(.+?)<bus31tor>")
      if match
        cap = match[1]
        decoded = @_rot13(cap)
        msg = msg.replace(new RegExp("<rot13sub>" + @quotemeta(cap) + "<bus31tor>", "g"), decoded)
      else
        @warn "Unknown fatal error! Saw a <rot13sub> but the regexp to find it failed!"
        return ""
    msg


  # Determine if a trigger is atomic or not.
  RiveScript::_is_atomic = (trigger) ->

    # Atomic triggers don't contain any wildcards or parenthesis or anything of the sort.
    # We don't need to test the full character set, just left brackets will do.
    special = [
      "*"
      "#"
      "_"
      "("
      "["
      "<"
    ]
    i = 0
    end = special.length

    while i < end
      return false  if trigger.indexOf(special[i]) > -1
      i++
    true


  #//////////////////////////////////////////////////////////////////////////
  # Topic Inheritence Utility Methods                                      //
  #//////////////////////////////////////////////////////////////////////////
  RiveScript::_topic_triggers = (topic, triglvl, depth, inheritence, inherited) ->

    # Initialize default values.
    depth = 0  unless depth?
    inheritence = 0  unless inheritence?
    inherited = 0  unless inherited?

    # Break if we're in too deep.
    if depth > @_depth
      @warn "Deep recursion while scanning topic inheritence!"
      return

    # Important info about the depth vs inheritence params to this function:
    # depth increments by 1 each time this function recursively calls itself.
    # inheritence increments by 1 only when this topic inherits another
    # topic.
    #
    # This way, '> topic alpha includes beta inherits gamma' will have this
    # effect:
    #  alpha and beta's triggers are combined together into one matching
    #  pool, and then those triggers have higher priority than gamma's.
    #
    # The inherited option is true if this is a recursive call, from a topic
    # that inherits other topics. This forces the {inherits} tag to be added
    # to the triggers. This only applies when the top topic 'includes'
    # another topic.
    @say "Collecting trigger list for topic " + topic + " (depth=" + depth + "; inheritence=" + inheritence + "; inherited=" + inherited + ")"

    # topic:   the name of the topic
    # triglvl: reference to this._topics or this._thats
    # depth:   starts at 0 and ++'s with each recursion.

    # Collect an array of triggers to return.
    triggers = []

    # Get those that exist in this topic directly.
    inThisTopic = []
    if triglvl[topic]
      for trigger of triglvl[topic]
        inThisTopic.push trigger

    # Does this topic include others?
    if @_includes[topic]

      # Check every included topic.
      for includes of @_includes[topic]
        @say "Topic " + topic + " includes " + includes
        triggers.push.apply triggers, @_topic_triggers(includes, triglvl, (depth + 1), (inheritence + 1), true)

    # Does this topic inherit others?
    if @_lineage[topic]

      # Check every inherited topic.
      for inherits of @_lineage[topic]
        @say "Topic " + topic + " inherits " + inherits
        triggers.push.apply triggers, @_topic_triggers(inherits, triglvl, (depth + 1), (inheritence + 1), false)

    # Collect the triggers for *this* topic. If this topic inherits any other
    # topics, it means that this topic's triggers have higher priority than
    # those in any inherited topics. Enforce this with an {inherits} tag.
    if @_lineage[topic] or inherited
      i = 0
      end = inThisTopic.length

      while i < end
        trigger = inThisTopic[i]
        @say "Prefixing trigger with {inherits=" + inheritence + "}" + trigger
        triggers.push.apply triggers, ["{inherits=" + inheritence + "}" + trigger]
        i++
    else
      triggers.push.apply triggers, inThisTopic
    triggers


  # Given a topic and a trigger, find the pointer to the trigger's data.
  # This will search the inheritence tree until it finds the topic that
  # the trigger exists in.
  RiveScript::_find_trigger_by_inheritence = (topic, trig, depth) ->

    # Prevent recursion.
    if depth > @_depth
      @warn "Deep recursion detected while following an inheritence trail!"
      return `undefined`

    # Inheritence is more important than inclusion: triggers in one topic can
    # override those in an inherited topic.
    if @_lineage[topic]
      for inherits of @_lineage[topic]

        # See if this inherited topic has our trigger.
        if @_topics[inherits][trig]

          # Great!
          return @_topics[inherits][trig]
        else

          # Check what THAT topic inherits from.
          match = @_find_trigger_by_inheritence(inherits, trig, (depth + 1))

          # Found it!
          return match  if match

    # See if this topic has an "includes".
    if @_includes[topic]
      for includes of @_includes[topic]

        # See if this included topic has our trigger.
        if @_topics[includes][trig]

          # It does!
          return @_topics[includes][trig]
        else

          # Check what THAT topic includes.
          match = @_find_trigger_by_inheritence(includes, trig, (depth + 1))

          # Found it!
          return match  if match

    # Not much else we can do!
    @warn "User matched a trigger, " + trig + ", but I can't find out what topic it belongs to!"
    `undefined`


  # Given a topic, this returns an array of every topic related to it (all the
  # topics it includes or inherits, plus all the topics included or inherited
  # by those topics, and so on). The array includes the original topic too.
  RiveScript::_get_topic_tree = (topic, depth) ->

    # Default depth.
    depth = 0  unless typeof (depth) is "number"

    # Break if we're in too deep.
    if depth > @_depth
      @warn "Deep recursion while scanning topic tree!"
      return []

    # Collect an array of all topics.
    topics = [topic]

    # Does this topic include others?
    if @_includes[topic]

      # Try each of these.
      for includes of @_includes[topic]
        topics.push.apply topics, @_get_topic_tree(includes, depth + 1)

    # Does this topic inherit other topics?
    if @_lineage[topic]

      # Try each of these.
      for inherits of @_lineage[topic]
        topics.push.apply topics, @_get_topic_tree(inherits, depth + 1)
    topics


  #//////////////////////////////////////////////////////////////////////////
  # Misc Utility Methods                                                   //
  #//////////////////////////////////////////////////////////////////////////

  # Strip whitespace from a string.
  RiveScript::_strip = (text) ->
    text = text.replace(/^[\s\t]+/i, "")
    text = text.replace(/[\s\t]+$/i, "")
    text = text.replace(/[\x0D\x0A]+/i, "")
    text


  # Count real words in a string.
  RiveScript::_word_count = (trigger, all) ->
    words = []
    if all
      words = trigger.split(/\s+/)
    else
      words = trigger.split(/[\s\*\#\_\|]+/)
    wc = 0
    i = 0
    end = words.length

    while i < end
      wc++  if words[i].length > 0
      i++
    wc


  # Escape a string for a regexp.
  RiveScript::quotemeta = (string) ->
    unsafe = "\\.+*?[^]$(){}=!<>|:"
    i = 0
    end = unsafe.length

    while i < end
      string = string.replace(new RegExp("\\" + unsafe.charAt(i), "g"), "\\" + unsafe.charAt(i))
      i++
    string


  # ROT13 encode a string.
  RiveScript::_rot13 = (string) ->
    result = ""
    i = 0
    end = string.length

    while i < end
      b = string.charCodeAt(i)
      if b >= 65 and b <= 77
        b += 13
      else if b >= 97 and b <= 109
        b += 13
      else if b >= 78 and b <= 90
        b -= 13
      else b -= 13  if b >= 110 and b <= 122
      result += String.fromCharCode(b)
      i++
    result


  # String formatting.
  RiveScript::_string_format = (type, string) ->
    if type is "uppercase"
      return string.toUpperCase()
    else if type is "lowercase"
      return string.toLowerCase()
    else if type is "sentence"
      string += ""
      first = string.charAt(0).toUpperCase()
      return first + string.substring(1)
    else if type is "formal"
      words = string.split(/\s+/)
      i = 0

      while i < words.length
        first = words[i].charAt(0).toUpperCase()
        words[i] = first + words[i].substring(1)
        i++
      return words.join(" ")
    string


  # Strip nasties.
  RiveScript::_strip_nasties = (string) ->
    string = string.replace(/[^A-Za-z0-9 ]/g, "")
    string


  # HTML escape.
  RiveScript::_escape_html = (string) ->
    string = string.replace(/&/g, "&amp;")
    string = string.replace(/</g, "&lt;")
    string = string.replace(/>/g, "&gt;")
    string = string.replace(/"/g, "&quot;")
    string


  # Clone an object.
  RiveScript::_clone = (obj) ->
    return obj  if obj is null or typeof (obj) isnt "object"
    copy = obj.constructor()
    for key of obj
      copy[key] = @_clone(obj[key])
    copy


  # Create Object.keys() because it doesn't exist.
  RiveScript::_shim_keys = ->
    unless Object.keys
      Object.keys = (->
        hasOwnProperty = Object::hasOwnProperty
        hasDontEnumBug = not (toString: null).propertyIsEnumerable("toString")
        dontEnums = [
          "toString"
          "toLocaleString"
          "valueOf"
          "hasOwnProperty"
          "isPrototypeOf"
          "propertyIsEnumerable"
          "constructor"
        ]
        dontEnumsLength = dontEnums.length
        (obj) ->
          throw new TypeError("Object.keys called on non-object")  if typeof (obj) isnt "object" and typeof (obj) isnt "function" or not obj?
          result = []
          for prop of obj
            result.push prop  if hasOwnProperty.call(obj, prop)
          if hasDontEnumBug
            i = 0

            while i < dontEnumsLength
              result.push dontEnums[i]  if hasOwnProperty.call(obj, dontEnums[i])
              i++
          result)()


if (typeof (module) is "undefined" and (typeof (window) isnt "undefined" and this is window)) then (a) ->
  this["RiveScript"] = a

else
(a) ->
  module.exports = a

a
