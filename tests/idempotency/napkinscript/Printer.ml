module Printer = struct
  let addParens doc =
    Doc.group (
      Doc.concat [
        Doc.lparen;
        Doc.indent (
          Doc.concat [
            Doc.softLine;
            doc
          ]
        );
        Doc.softLine;
        Doc.rparen;
      ]
    )

  let addBraces doc =
    Doc.group (
      Doc.concat [
        Doc.lbrace;
        doc;
        Doc.rbrace;
      ]
    )

  let getFirstLeadingComment tbl loc =
    match Hashtbl.find tbl.CommentTable.leading loc with
    | comment::_ -> Some comment
    | [] -> None
    | exception Not_found -> None

  let printMultilineCommentContent txt =
    (* Turns
     *         |* first line
     *  * second line
     *      * third line *|
     * Into
     * |* first line
     *  * second line
     *  * third line *|
     *
     * What makes a comment suitable for this kind of indentation?
     *  ->  multiple lines + every line starts with a star
     *)
    let rec indentStars lines acc =
      match lines with
      | [] -> Doc.nil
      | [lastLine] ->
        let line = String.trim lastLine in
        let doc = Doc.text (" " ^ line) in
        let trailingSpace = if String.length line > 0 then Doc.space else Doc.nil in
        List.rev (trailingSpace::doc::acc) |> Doc.concat
      | line::lines ->
        let line = String.trim line in
        let len = String.length line in
        if len > 0 && String.get line 0 == '*' then
          let doc = Doc.text (" " ^ (String.trim line)) in
          indentStars lines (Doc.hardLine::doc::acc)
        else
          let trailingSpace =
            let len = String.length txt in
            if len > 0 && (String.unsafe_get txt (len - 1) = ' ') then
              Doc.space
            else Doc.nil
          in
          let content = Comment.trimSpaces txt in
          Doc.concat [Doc.text content; trailingSpace]
    in
    let lines = String.split_on_char '\n' txt in
    match lines with
    | [] -> Doc.text "/* */"
    | [line] -> Doc.concat [
        Doc.text "/* ";
        Doc.text (Comment.trimSpaces line);
        Doc.text " */";
      ]
    | first::rest ->
      let firstLine = Comment.trimSpaces first in
      Doc.concat [
        Doc.text "/*";
        if String.length firstLine > 0 && not (String.equal firstLine "*") then
          Doc.space else Doc.nil;
        indentStars rest [Doc.hardLine; Doc.text firstLine];
        Doc.text "*/";
      ]

  let printTrailingComment (nodeLoc : Location.t) comment =
    let singleLine = Comment.isSingleLineComment comment in
    let content =
      let txt = Comment.txt comment in
      if singleLine then
         Doc.text ("// " ^ String.trim txt)
      else
        printMultilineCommentContent txt
    in
    let diff =
      let cmtStart = (Comment.loc comment).loc_start in
      let prevTokEndPos = Comment.prevTokEndPos comment in
      cmtStart.pos_lnum - prevTokEndPos.pos_lnum
    in
    let isBelow =
      (Comment.loc comment).loc_start.pos_lnum > nodeLoc.loc_end.pos_lnum in
    if diff > 0 || isBelow then
      Doc.lineSuffix(
        (Doc.concat [Doc.hardLine; if diff > 1 then Doc.hardLine else Doc.nil; content])
      )
    else if not singleLine then
      Doc.concat [Doc.space; content]
    else
      Doc.lineSuffix (Doc.concat [Doc.space; content])

  let printLeadingComment ?nextComment comment =
    let singleLine = Comment.isSingleLineComment comment in
    let content =
      let txt = Comment.txt comment in
      if singleLine then
         Doc.text ("// " ^ String.trim txt)
      else
        printMultilineCommentContent txt
    in
    let separator = Doc.concat  [
      if singleLine then Doc.concat [
        Doc.hardLine;
        Doc.breakParent;
      ] else Doc.nil;
      (match nextComment with
      | Some next ->
        let nextLoc = Comment.loc next in
        let currLoc = Comment.loc comment in
        let diff =
          nextLoc.Location.loc_start.pos_lnum -
          currLoc.Location.loc_end.pos_lnum
        in
        let nextSingleLine = Comment.isSingleLineComment next in
        if singleLine && nextSingleLine then
          if diff > 1 then Doc.hardLine else Doc.nil
        else if singleLine && not nextSingleLine then
          if diff > 1 then Doc.hardLine else Doc.nil
        else
          if diff > 1 then Doc.concat [Doc.hardLine; Doc.hardLine]
          else if diff == 1 then Doc.hardLine
          else
            Doc.space
      | None -> Doc.nil)
    ]
    in
    Doc.concat [
      content;
      separator;
    ]

  let printCommentsInside cmtTbl loc =
    let rec loop acc comments =
      match comments with
      | [] -> Doc.nil
      | [comment] ->
        let cmtDoc = printLeadingComment comment in
        let doc = Doc.group (
          Doc.concat [
            Doc.concat (List.rev (cmtDoc::acc));
          ]
        )
        in
        doc
      | comment::((nextComment::comments) as rest) ->
        let cmtDoc = printLeadingComment ~nextComment comment in
        loop (cmtDoc::acc) rest
    in
    match Hashtbl.find cmtTbl.CommentTable.inside loc with
    | exception Not_found -> Doc.nil
    | comments ->
      Hashtbl.remove cmtTbl.inside loc;
      Doc.group (
        loop [] comments
      )

  let printLeadingComments node tbl loc =
    let rec loop acc comments =
      match comments with
      | [] -> node
      | [comment] ->
        let cmtDoc = printLeadingComment comment in
        let diff =
          loc.Location.loc_start.pos_lnum -
          (Comment.loc comment).Location.loc_end.pos_lnum
        in
        let separator =
          if Comment.isSingleLineComment comment then
            if diff > 1 then Doc.hardLine else Doc.nil
          else if diff == 0 then
           Doc.space
          else if diff > 1 then Doc.concat [Doc.hardLine; Doc.hardLine]
          else
           Doc.hardLine
        in
        let doc = Doc.group (
          Doc.concat [
            Doc.concat (List.rev (cmtDoc::acc));
            separator;
            node
          ]
        )
        in
        doc
      | comment::((nextComment::comments) as rest) ->
        let cmtDoc = printLeadingComment ~nextComment comment in
        loop (cmtDoc::acc) rest
    in
    match Hashtbl.find tbl loc with
    | exception Not_found -> node
    | comments ->
     (* Remove comments from tbl: Some ast nodes have the same location.
      * We only want to print comments once *)
      Hashtbl.remove tbl loc;
      loop [] comments

  let printTrailingComments node tbl loc =
    let rec loop acc comments =
      match comments with
      | [] -> Doc.concat (List.rev acc)
      | comment::comments ->
        let cmtDoc = printTrailingComment loc comment in
        loop (cmtDoc::acc) comments
    in
    match Hashtbl.find tbl loc with
    | exception Not_found -> node
    | [] -> node
    | (first::_) as comments ->
     (* Remove comments from tbl: Some ast nodes have the same location.
      * We only want to print comments once *)
      Hashtbl.remove tbl loc;
      let cmtsDoc = loop [] comments in
      Doc.concat [
        node;
        cmtsDoc;
      ]

  let printComments doc (tbl: CommentTable.t) loc =
    let docWithLeadingComments = printLeadingComments doc tbl.leading loc in
    printTrailingComments docWithLeadingComments tbl.trailing loc

  let printLoc (loc: Location.t) =
    Format.sprintf "{start: %d-%d; end: %d-%d}"
      loc.loc_start.pos_lnum
      (loc.loc_start.pos_cnum - loc.loc_start.pos_bol)
      loc.loc_end.pos_lnum
      (loc.loc_end.pos_cnum - loc.loc_end.pos_bol)
    |> print_endline

  let printList ~getLoc ~nodes ~print ?(forceBreak=false) t =
    let rec loop (prevLoc: Location.t) acc nodes =
      match nodes with
      | [] -> (prevLoc, Doc.concat (List.rev acc))
      | node::nodes ->
        let loc = getLoc node in
        let startPos = match getFirstLeadingComment t loc with
        | None -> loc.loc_start
        | Some comment -> (Comment.loc comment).loc_start
        in
        let sep = if startPos.pos_lnum - prevLoc.loc_end.pos_lnum > 1 then
          Doc.concat [Doc.hardLine; Doc.hardLine]
        else
          Doc.hardLine
        in
        let doc = printComments (print node t) t loc in
        loop loc (doc::sep::acc) nodes
    in
    match nodes with
    | [] -> Doc.nil
    | node::nodes ->
      let firstLoc = getLoc node in
      let doc = printComments (print node t) t firstLoc in
      let (lastLoc, docs) = loop firstLoc [doc] nodes in
      let forceBreak =
        forceBreak ||
        firstLoc.loc_start.pos_lnum != lastLoc.loc_end.pos_lnum
      in
      Doc.breakableGroup ~forceBreak docs

  let printListi ~getLoc ~nodes ~print ?(forceBreak=false) t =
    let rec loop i (prevLoc: Location.t) acc nodes =
      match nodes with
      | [] -> (prevLoc, Doc.concat (List.rev acc))
      | node::nodes ->
        let loc = getLoc node in
        let startPos = match getFirstLeadingComment t loc with
        | None -> loc.loc_start
        | Some comment -> (Comment.loc comment).loc_start
        in
        let sep = if startPos.pos_lnum - prevLoc.loc_end.pos_lnum > 1 then
          Doc.concat [Doc.hardLine; Doc.hardLine]
        else
          Doc.line
        in
        let doc = printComments (print node t i) t loc in
        loop (i + 1) loc (doc::sep::acc) nodes
    in
    match nodes with
    | [] -> Doc.nil
    | node::nodes ->
      let firstLoc = getLoc node in
      let doc = printComments (print node t 0) t firstLoc in
      let (lastLoc, docs) = loop 1 firstLoc [doc] nodes in
      let forceBreak =
        forceBreak ||
        firstLoc.loc_start.pos_lnum != lastLoc.loc_end.pos_lnum
      in
      Doc.breakableGroup ~forceBreak docs

  (* This could be done in one pass by collecting locations as we go? *)
  let interleaveWhitespace ?(forceBreak=false) (rows: (Location.t * Doc.t) list) =
    let rec loop prevLoc acc rows =
      match rows with
      | [] -> Doc.concat (List.rev acc)
      | (loc, doc)::rest ->
        if loc.Location.loc_start.pos_lnum - prevLoc.Location.loc_end.pos_lnum > 1 then
          loop loc (doc::Doc.line::Doc.line::acc) rest
        else
          loop loc (doc::Doc.line::acc) rest
    in
    match rows with
    | [] -> Doc.nil
    | (firstLoc, firstDoc)::rest ->
      (* TODO: perf, reversing the list twice! *)
      let forceBreak = forceBreak || (match List.rev rest with
      | (lastLoc, _)::_ ->
        firstLoc.loc_start.pos_lnum != lastLoc.loc_end.pos_lnum
      | _ -> false)
      in
      Doc.breakableGroup ~forceBreak (
        loop firstLoc [firstDoc] rest
      )

  type identifierStyle =
    | ExoticIdent
    | NormalIdent

  let classifyIdentContent txt =
    let len = String.length txt in
    let rec go i =
      if i == len then NormalIdent
      else
        let c = String.unsafe_get txt i in
        if i == 0 && not ((c >= 'a' && c <= 'z') || c = '_' || (c >= '0' && c <= '9')) then
          ExoticIdent
        else if not (
             (c >= 'a' && c <= 'z')
          || (c >= 'A' && c <= 'Z')
          || c = '\''
          || c = '_'
          || (c >= '0' && c <= '9'))
        then
          ExoticIdent
        else
          go (i + 1)
    in
    if Token.isKeywordTxt txt then
      ExoticIdent
    else
      go 0

  let printIdentLike txt =
    match classifyIdentContent txt with
    | ExoticIdent -> Doc.concat [
        Doc.text "\\\"";
        Doc.text txt;
        Doc.text"\""
      ]
    | NormalIdent -> Doc.text txt

  let printLongident l = match l with
    | Longident.Lident txt -> Doc.text txt
    | Longident.Ldot (lident, txt) as l ->
      let txts = Longident.flatten l in
      Doc.join ~sep:Doc.dot (List.map Doc.text txts)
    | _ -> failwith "unsupported ident"

  let printLongidentLocation l cmtTbl =
    let doc = printLongident l.Location.txt in
    printComments doc cmtTbl l.loc

  let printStringLoc sloc cmtTbl =
    let doc = printIdentLike sloc.Location.txt in
    printComments doc cmtTbl sloc.loc

  (* TODO: better allocation strategy for the buffer *)
  let escapeStringContents s =
    let len = String.length s in
    let b = Buffer.create len in
    for i = 0 to len - 1 do
      let c = String.get s i in
      if c = '\008'  then (
        Buffer.add_char b '\\';
        Buffer.add_char b 'b';
      ) else if c = '\009'  then (
        Buffer.add_char b '\\';
        Buffer.add_char b 't';
      ) else if c = '\010' then (
        Buffer.add_char b '\\';
        Buffer.add_char b 'n';
      ) else if c = '\013' then (
        Buffer.add_char b '\\';
        Buffer.add_char b 'r';
      ) else if c = '\034' then (
        Buffer.add_char b '\\';
        Buffer.add_char b '"';
      ) else if c = '\092' then (
        Buffer.add_char b '\\';
        Buffer.add_char b '\\';
      ) else (
        Buffer.add_char b c;
      );
    done;
    Buffer.contents b

  let printConstant c = match c with
    | Parsetree.Pconst_integer (s, suffix) ->
      begin match suffix with
      | Some c -> Doc.text (s ^ (Char.escaped c))
      | None -> Doc.text s
      end
    | Pconst_string (txt, None) ->
        Doc.text ("\"" ^ (escapeStringContents txt) ^ "\"")
    | Pconst_string (txt, Some prefix) ->
      Doc.concat [
        if prefix = "j" then Doc.nil else Doc.text prefix;
        Doc.text ("`" ^ txt ^ "`")
      ]
    | Pconst_float (s, _) -> Doc.text s
    | Pconst_char c -> Doc.text ("'" ^ (Char.escaped c) ^ "'")

  let rec printStructure (s : Parsetree.structure) t =
    match s with
    | [] -> printCommentsInside t Location.none
    | structure ->
      printList
        ~getLoc:(fun s -> s.Parsetree.pstr_loc)
        ~nodes:structure
        ~print:printStructureItem
        t

  and printStructureItem (si: Parsetree.structure_item) cmtTbl =
    match si.pstr_desc with
    | Pstr_value(rec_flag, valueBindings) ->
			let recFlag = match rec_flag with
			| Asttypes.Nonrecursive -> Doc.nil
			| Asttypes.Recursive -> Doc.text "rec "
			in
      printValueBindings ~recFlag valueBindings cmtTbl
    | Pstr_type(recFlag, typeDeclarations) ->
      let recFlag = match recFlag with
      | Asttypes.Nonrecursive -> Doc.nil
      | Asttypes.Recursive -> Doc.text "rec "
      in
      printTypeDeclarations ~recFlag typeDeclarations cmtTbl
    | Pstr_primitive valueDescription ->
      printValueDescription valueDescription cmtTbl
    | Pstr_eval (expr, attrs) ->
      let exprDoc =
        let doc = printExpressionWithComments expr cmtTbl in
        match Parens.structureExpr expr with
        | Parens.Parenthesized -> addParens doc
        | Braced braces  -> printBraces doc expr braces
        | Nothing -> doc
      in
      Doc.concat [
        printAttributes attrs;
        exprDoc;
      ]
    | Pstr_attribute attr -> Doc.concat [
        Doc.text "@";
        printAttributeWithComments attr cmtTbl
      ]
    | Pstr_extension (extension, attrs) -> Doc.concat [
        printAttributes attrs;
        Doc.concat [Doc.text "%"; printExtensionWithComments extension cmtTbl];
      ]
    | Pstr_include includeDeclaration ->
      printIncludeDeclaration includeDeclaration cmtTbl
    | Pstr_open openDescription ->
      printOpenDescription openDescription cmtTbl
    | Pstr_modtype modTypeDecl ->
      printModuleTypeDeclaration modTypeDecl cmtTbl
    | Pstr_module moduleBinding ->
      printModuleBinding ~isRec:false moduleBinding cmtTbl 0
    | Pstr_recmodule moduleBindings ->
      printListi
        ~getLoc:(fun mb -> mb.Parsetree.pmb_loc)
        ~nodes:moduleBindings
        ~print:(printModuleBinding ~isRec:true)
        cmtTbl
    | Pstr_exception extensionConstructor ->
      printExceptionDef extensionConstructor cmtTbl
    | Pstr_typext typeExtension ->
      printTypeExtension typeExtension cmtTbl
    | Pstr_class _ | Pstr_class_type _ -> Doc.nil

  and printTypeExtension (te : Parsetree.type_extension) cmtTbl =
    let prefix = Doc.text "type " in
    let name = printLongidentLocation te.ptyext_path cmtTbl in
    let typeParams = printTypeParams te.ptyext_params cmtTbl in
    let extensionConstructors =
      let ecs = te.ptyext_constructors in
      let forceBreak =
        match (ecs, List.rev ecs) with
        | (first::_, last::_) ->
          first.pext_loc.loc_start.pos_lnum > te.ptyext_path.loc.loc_end.pos_lnum ||
          first.pext_loc.loc_start.pos_lnum < last.pext_loc.loc_end.pos_lnum
        | _ -> false
        in
      let privateFlag = match te.ptyext_private with
      | Asttypes.Private -> Doc.concat [
          Doc.text "private";
          Doc.line;
        ]
      | Public -> Doc.nil
      in
      let rows =
        printListi
         ~getLoc:(fun n -> n.Parsetree.pext_loc)
         ~print:printExtensionConstructor
         ~nodes: ecs
         ~forceBreak
         cmtTbl
      in
      Doc.breakableGroup ~forceBreak (
        Doc.indent (
          Doc.concat [
            Doc.line;
            privateFlag;
            rows;
          ]
        )
      )
    in
    Doc.group (
      Doc.concat [
        printAttributes ~loc: te.ptyext_path.loc te.ptyext_attributes;
        prefix;
        name;
        typeParams;
        Doc.text " +=";
        extensionConstructors;
      ]
    )

  and printModuleBinding ~isRec moduleBinding cmtTbl i =
    let prefix = if i = 0 then
      Doc.concat [
        Doc.text "module ";
        if isRec then Doc.text "rec " else Doc.nil;
      ]
    else
      Doc.text "and "
    in
    let (modExprDoc, modConstraintDoc) =
      match moduleBinding.pmb_expr with
      | {pmod_desc = Pmod_constraint (modExpr, modType)} ->
        (
          printModExpr modExpr cmtTbl,
          Doc.concat [
            Doc.text ": ";
            printModType modType cmtTbl
          ]
        )
      | modExpr ->
        (printModExpr modExpr cmtTbl, Doc.nil)
    in
    let modName =
      let doc = Doc.text moduleBinding.pmb_name.Location.txt in
      printComments doc cmtTbl moduleBinding.pmb_name.loc
    in
    let doc = Doc.concat [
      printAttributes ~loc:moduleBinding.pmb_name.loc moduleBinding.pmb_attributes;
      prefix;
      modName;
      modConstraintDoc;
      Doc.text " = ";
      modExprDoc;
    ] in
    printComments doc cmtTbl moduleBinding.pmb_loc

  and printModuleTypeDeclaration (modTypeDecl : Parsetree.module_type_declaration) cmtTbl =
    let modName =
      let doc = Doc.text modTypeDecl.pmtd_name.txt in
      printComments doc cmtTbl modTypeDecl.pmtd_name.loc
    in
    Doc.concat [
      printAttributes modTypeDecl.pmtd_attributes;
      Doc.text "module type ";
      modName;
      (match modTypeDecl.pmtd_type with
      | None -> Doc.nil
      | Some modType -> Doc.concat [
          Doc.text " = ";
          printModType modType cmtTbl;
        ]);
    ]

  and printModType modType cmtTbl =
    let modTypeDoc = match modType.pmty_desc with
    | Parsetree.Pmty_ident longident ->
      Doc.concat [
        printAttributes ~loc:longident.loc modType.pmty_attributes;
        printLongidentLocation longident cmtTbl
      ]
    | Pmty_signature signature ->
      let signatureDoc = Doc.breakableGroup ~forceBreak:true (
        Doc.concat [
          Doc.lbrace;
          Doc.indent (
            Doc.concat [
              Doc.line;
              printSignature signature cmtTbl;
            ]
          );
          Doc.line;
          Doc.rbrace;
        ]
      ) in
      Doc.concat [
        printAttributes modType.pmty_attributes;
        signatureDoc
      ]
    | Pmty_functor _ ->
      let (parameters, returnType) = ParsetreeViewer.functorType modType in
      let parametersDoc = match parameters with
      | [] -> Doc.nil
      | [attrs, {Location.txt = "_"; loc}, Some modType] ->
        let cmtLoc =
          {loc with loc_end = modType.Parsetree.pmty_loc.loc_end}
        in
        let attrs = match attrs with
        | [] -> Doc.nil
        | attrs -> Doc.concat [
          Doc.join ~sep:Doc.line (List.map printAttribute attrs);
          Doc.line;
        ] in
        let doc = Doc.concat [
          attrs;
          printModType modType cmtTbl
        ] in
        printComments doc cmtTbl cmtLoc
      | params ->
        Doc.group (
          Doc.concat [
            Doc.lparen;
            Doc.indent (
              Doc.concat [
                Doc.softLine;
                Doc.join ~sep:(Doc.concat [Doc.comma; Doc.line]) (
                  List.map (fun (attrs, lbl, modType) ->
                    let cmtLoc = match modType with
                    | None -> lbl.Asttypes.loc
                    | Some modType ->
                      {lbl.Asttypes.loc with loc_end = modType.Parsetree.pmty_loc.loc_end}
                    in
                    let attrs = match attrs with
                    | [] -> Doc.nil
                    | attrs -> Doc.concat [
                      Doc.join ~sep:Doc.line (List.map printAttribute attrs);
                      Doc.line;
                    ] in
                    let lblDoc = if lbl.Location.txt = "_" then Doc.nil
                      else
                        let doc = Doc.text lbl.txt in
                        printComments doc cmtTbl lbl.loc
                    in
                    let doc = Doc.concat [
                      attrs;
                      lblDoc;
                      (match modType with
                      | None -> Doc.nil
                      | Some modType -> Doc.concat [
                        if lbl.txt = "_" then Doc.nil else Doc.text ": ";
                        printModType modType cmtTbl;
                      ]);
                    ] in
                    printComments doc cmtTbl cmtLoc
                  ) params
                );
              ]
            );
            Doc.trailingComma;
            Doc.softLine;
            Doc.rparen;
          ]
        )
      in
      let returnDoc =
        let doc = printModType returnType cmtTbl in
        if Parens.modTypeFunctorReturn returnType then addParens doc else doc
      in
      Doc.group (
        Doc.concat [
          parametersDoc;
          Doc.group (
            Doc.concat [
            Doc.text " =>";
            Doc.line;
            returnDoc;
            ]
          )
        ]
      )
    | Pmty_typeof modExpr -> Doc.concat [
        Doc.text "module type of ";
        printModExpr modExpr cmtTbl
      ]
    | Pmty_extension extension -> printExtensionWithComments extension cmtTbl
    | Pmty_alias longident -> Doc.concat [
        Doc.text "module ";
        printLongidentLocation longident cmtTbl;
      ]
    | Pmty_with (modType, withConstraints) ->
      let operand =
        let doc = printModType modType cmtTbl in
        if Parens.modTypeWithOperand modType then addParens doc else doc
      in
      Doc.group (
        Doc.concat [
          operand;
          Doc.indent (
            Doc.concat [
              Doc.line;
              printWithConstraints withConstraints;
            ]
          )
        ]
      )
    in
    let attrsAlreadyPrinted = match modType.pmty_desc with
    | Pmty_functor _ | Pmty_signature _ | Pmty_ident _ -> true
    | _ -> false
    in
    let doc =Doc.concat [
      if attrsAlreadyPrinted then Doc.nil else printAttributes modType.pmty_attributes;
      modTypeDoc;
    ] in
    printComments doc cmtTbl modType.pmty_loc

  and printWithConstraints withConstraints =
    let rows =List.mapi (fun i withConstraint  ->
      Doc.group (
        Doc.concat [
          if i == 0 then Doc.text "with " else Doc.text "and ";
          printWithConstraint withConstraint;
        ]
      )
    ) withConstraints
    in
    Doc.join ~sep:Doc.line rows

  and printWithConstraint (withConstraint : Parsetree.with_constraint) =
    match withConstraint with
    (* with type X.t = ... *)
    | Pwith_type ({txt = longident}, typeDeclaration) ->
      Doc.group (printTypeDeclaration
        ~name:(printLongident longident)
        ~equalSign:"="
        ~recFlag:Doc.nil
        0
        typeDeclaration
        CommentTable.empty)
    (* with module X.Y = Z *)
    | Pwith_module ({txt = longident1}, {txt = longident2}) ->
        Doc.concat [
          Doc.text "module ";
          printLongident longident1;
          Doc.text " =";
          Doc.indent (
            Doc.concat [
              Doc.line;
              printLongident longident2;
            ]
          )
        ]
    (* with type X.t := ..., same format as [Pwith_type] *)
    | Pwith_typesubst ({txt = longident}, typeDeclaration) ->
      Doc.group(printTypeDeclaration
        ~name:(printLongident longident)
        ~equalSign:":="
        ~recFlag:Doc.nil
        0
        typeDeclaration
        CommentTable.empty)
    | Pwith_modsubst ({txt = longident1}, {txt = longident2}) ->
      Doc.concat [
        Doc.text "module ";
        printLongident longident1;
        Doc.text " :=";
        Doc.indent (
          Doc.concat [
            Doc.line;
            printLongident longident2;
          ]
        )
      ]

  and printSignature signature cmtTbl =
    match signature with
    | [] -> printCommentsInside cmtTbl Location.none
    | signature ->
      printList
        ~getLoc:(fun s -> s.Parsetree.psig_loc)
        ~nodes:signature
        ~print:printSignatureItem
        cmtTbl

  and printSignatureItem (si : Parsetree.signature_item) cmtTbl =
    match si.psig_desc with
    | Parsetree.Psig_value valueDescription ->
      printValueDescription valueDescription cmtTbl
    | Psig_type (recFlag, typeDeclarations) ->
      let recFlag = match recFlag with
      | Asttypes.Nonrecursive -> Doc.nil
      | Asttypes.Recursive -> Doc.text "rec "
      in
      printTypeDeclarations ~recFlag typeDeclarations cmtTbl
    | Psig_typext typeExtension ->
      printTypeExtension typeExtension cmtTbl
    | Psig_exception extensionConstructor ->
      printExceptionDef extensionConstructor cmtTbl
    | Psig_module moduleDeclaration ->
      printModuleDeclaration moduleDeclaration cmtTbl
    | Psig_recmodule moduleDeclarations ->
      printRecModuleDeclarations moduleDeclarations cmtTbl
    | Psig_modtype modTypeDecl ->
      printModuleTypeDeclaration modTypeDecl cmtTbl
    | Psig_open openDescription ->
      printOpenDescription openDescription cmtTbl
    | Psig_include includeDescription ->
      printIncludeDescription includeDescription cmtTbl
    | Psig_attribute attr -> Doc.concat [
        Doc.text "@";
        printAttributeWithComments attr cmtTbl
      ]
    | Psig_extension (extension, attrs) -> Doc.concat [
        printAttributes attrs;
        Doc.concat [Doc.text "%"; printExtensionWithComments extension cmtTbl];
      ]
    | Psig_class _ | Psig_class_type _ -> Doc.nil

  and printRecModuleDeclarations moduleDeclarations cmtTbl =
      printListi
        ~getLoc:(fun n -> n.Parsetree.pmd_loc)
        ~nodes:moduleDeclarations
        ~print:printRecModuleDeclaration
        cmtTbl

 and printRecModuleDeclaration md cmtTbl i =
    let body = match md.pmd_type.pmty_desc with
    | Parsetree.Pmty_alias longident ->
      Doc.concat [Doc.text " = "; printLongidentLocation longident cmtTbl]
    | _ ->
      let needsParens = match md.pmd_type.pmty_desc with
      | Pmty_with _ -> true
      | _ -> false
      in
      let modTypeDoc =
        let doc = printModType md.pmd_type cmtTbl in
        if needsParens then addParens doc else doc
      in
      Doc.concat [Doc.text ": "; modTypeDoc]
    in
    let prefix = if i < 1 then "module rec " else "and " in
    Doc.concat [
      printAttributes ~loc:md.pmd_name.loc md.pmd_attributes;
      Doc.text prefix;
      printComments (Doc.text md.pmd_name.txt) cmtTbl md.pmd_name.loc;
      body
    ]

  and printModuleDeclaration (md: Parsetree.module_declaration) cmtTbl =
    let body = match md.pmd_type.pmty_desc with
    | Parsetree.Pmty_alias longident ->
      Doc.concat [Doc.text " = "; printLongidentLocation longident cmtTbl]
    | _ -> Doc.concat [Doc.text ": "; printModType md.pmd_type cmtTbl]
    in
    Doc.concat [
      printAttributes ~loc:md.pmd_name.loc md.pmd_attributes;
      Doc.text "module ";
      printComments (Doc.text md.pmd_name.txt) cmtTbl md.pmd_name.loc;
      body
    ]

  and printOpenDescription (openDescription : Parsetree.open_description) p =
    Doc.concat [
      printAttributes openDescription.popen_attributes;
      Doc.text "open";
      (match openDescription.popen_override with
      | Asttypes.Fresh -> Doc.space
      | Asttypes.Override -> Doc.text "! ");
      printLongidentLocation openDescription.popen_lid p
    ]

  and printIncludeDescription (includeDescription: Parsetree.include_description) cmtTbl =
    Doc.concat [
      printAttributes includeDescription.pincl_attributes;
      Doc.text "include ";
      printModType includeDescription.pincl_mod cmtTbl;
    ]

  and printIncludeDeclaration (includeDeclaration : Parsetree.include_declaration)  cmtTbl=
    Doc.concat [
      printAttributes includeDeclaration.pincl_attributes;
      Doc.text "include ";
      printModExpr includeDeclaration.pincl_mod cmtTbl;
    ]

  and printValueBindings ~recFlag (vbs: Parsetree.value_binding list) cmtTbl =
    printListi
      ~getLoc:(fun vb -> vb.Parsetree.pvb_loc)
      ~nodes:vbs
      ~print:(printValueBinding ~recFlag)
      cmtTbl

  and printValueDescription valueDescription cmtTbl =
    let isExternal =
      match valueDescription.pval_prim with | [] -> false | _ -> true
    in
    Doc.group (
      Doc.concat [
        printAttributes valueDescription.pval_attributes;
        Doc.text (if isExternal then "external " else "let ");
        printComments
          (Doc.text valueDescription.pval_name.txt)
          cmtTbl
          valueDescription.pval_name.loc;
        Doc.text ": ";
        printTypExpr valueDescription.pval_type cmtTbl;
        if isExternal then
          Doc.group (
            Doc.concat [
              Doc.text " =";
              Doc.indent(
                Doc.concat [
                  Doc.line;
                  Doc.join ~sep:Doc.line (
                    List.map(fun s -> Doc.concat [
                      Doc.text "\"";
                      Doc.text s;
                      Doc.text "\"";
                    ])
                    valueDescription.pval_prim
                  );
                ]
              )
            ]
          )
        else Doc.nil
      ]
    )

  and printTypeDeclarations ~recFlag typeDeclarations cmtTbl =
    printListi
      ~getLoc:(fun n -> n.Parsetree.ptype_loc)
      ~nodes:typeDeclarations
      ~print:(printTypeDeclaration2 ~recFlag)
      cmtTbl

  (*
   * type_declaration = {
   *    ptype_name: string loc;
   *    ptype_params: (core_type * variance) list;
   *          (* ('a1,...'an) t; None represents  _*)
   *    ptype_cstrs: (core_type * core_type * Location.t) list;
   *          (* ... constraint T1=T1'  ... constraint Tn=Tn' *)
   *    ptype_kind: type_kind;
   *    ptype_private: private_flag;   (* = private ... *)
   *    ptype_manifest: core_type option;  (* = T *)
   *    ptype_attributes: attributes;   (* ... [@@id1] [@@id2] *)
   *    ptype_loc: Location.t;
   * }
   *
   *
   *  type t                     (abstract, no manifest)
   *  type t = T0                (abstract, manifest=T0)
   *  type t = C of T | ...      (variant,  no manifest)
   *  type t = T0 = C of T | ... (variant,  manifest=T0)
   *  type t = {l: T; ...}       (record,   no manifest)
   *  type t = T0 = {l : T; ...} (record,   manifest=T0)
   *  type t = ..                (open,     no manifest)
   *
   *
   * and type_kind =
   *  | Ptype_abstract
   *  | Ptype_variant of constructor_declaration list
   *        (* Invariant: non-empty list *)
   *  | Ptype_record of label_declaration list
   *        (* Invariant: non-empty list *)
   *  | Ptype_open
   *)
  and printTypeDeclaration ~name ~equalSign ~recFlag i (td: Parsetree.type_declaration) cmtTbl =
    let (hasGenType, attrs) = ParsetreeViewer.splitGenTypeAttr td.ptype_attributes in
    let attrs = printAttributes ~loc:td.ptype_loc attrs in
    let prefix = if i > 0 then
      Doc.concat [
        Doc.text "and ";
        if hasGenType then Doc.text "export " else Doc.nil
      ]
    else
      Doc.concat [
        Doc.text (if hasGenType then "export type " else "type ");
        recFlag
      ]
    in
    let typeName = name in
    let typeParams = printTypeParams td.ptype_params cmtTbl in
    let manifestAndKind = match td.ptype_kind with
    | Ptype_abstract ->
      begin match td.ptype_manifest with
      | None -> Doc.nil
      | Some(typ) ->
        Doc.concat [
          Doc.concat [Doc.space; Doc.text equalSign; Doc.space];
          printPrivateFlag td.ptype_private;
          printTypExpr typ cmtTbl;
        ]
      end
    | Ptype_open -> Doc.concat [
        Doc.concat [Doc.space; Doc.text equalSign; Doc.space];
        printPrivateFlag td.ptype_private;
        Doc.text "..";
      ]
    | Ptype_record(lds) ->
      let manifest = match td.ptype_manifest with
      | None -> Doc.nil
      | Some(typ) -> Doc.concat [
          Doc.concat [Doc.space; Doc.text equalSign; Doc.space];
          printTypExpr typ cmtTbl;
        ]
      in
      Doc.concat [
        manifest;
        Doc.concat [Doc.space; Doc.text equalSign; Doc.space];
        printPrivateFlag td.ptype_private;
        printRecordDeclaration lds cmtTbl;
      ]
    | Ptype_variant(cds) ->
      let manifest = match td.ptype_manifest with
      | None -> Doc.nil
      | Some(typ) -> Doc.concat [
          Doc.concat [Doc.space; Doc.text equalSign; Doc.space];
          printTypExpr typ cmtTbl;
        ]
      in
      Doc.concat [
        manifest;
        Doc.concat [Doc.space; Doc.text equalSign];
        printConstructorDeclarations ~privateFlag:td.ptype_private cds cmtTbl;
      ]
    in
    let constraints = printTypeDefinitionConstraints td.ptype_cstrs in
    Doc.group (
      Doc.concat [
        attrs;
        prefix;
        typeName;
        typeParams;
        manifestAndKind;
        constraints;
      ]
    )

  and printTypeDeclaration2 ~recFlag (td: Parsetree.type_declaration) cmtTbl i =
    let name =
      let doc = printIdentLike td.Parsetree.ptype_name.txt in
      printComments doc cmtTbl td.ptype_name.loc
    in
    let equalSign = "=" in
    let (hasGenType, attrs) = ParsetreeViewer.splitGenTypeAttr td.ptype_attributes in
    let attrs = printAttributes ~loc:td.ptype_loc attrs in
    let prefix = if i > 0 then
      Doc.concat [
        Doc.text "and ";
        if hasGenType then Doc.text "export " else Doc.nil
      ]
    else
      Doc.concat [
        Doc.text (if hasGenType then "export type " else "type ");
        recFlag
      ]
    in
    let typeName = name in
    let typeParams = printTypeParams td.ptype_params cmtTbl in
    let manifestAndKind = match td.ptype_kind with
    | Ptype_abstract ->
      begin match td.ptype_manifest with
      | None -> Doc.nil
      | Some(typ) ->
        Doc.concat [
          Doc.concat [Doc.space; Doc.text equalSign; Doc.space];
          printPrivateFlag td.ptype_private;
          printTypExpr typ cmtTbl;
        ]
      end
    | Ptype_open -> Doc.concat [
        Doc.concat [Doc.space; Doc.text equalSign; Doc.space];
        printPrivateFlag td.ptype_private;
        Doc.text "..";
      ]
    | Ptype_record(lds) ->
      let manifest = match td.ptype_manifest with
      | None -> Doc.nil
      | Some(typ) -> Doc.concat [
          Doc.concat [Doc.space; Doc.text equalSign; Doc.space];
          printTypExpr typ cmtTbl;
        ]
      in
      Doc.concat [
        manifest;
        Doc.concat [Doc.space; Doc.text equalSign; Doc.space];
        printPrivateFlag td.ptype_private;
        printRecordDeclaration lds cmtTbl;
      ]
    | Ptype_variant(cds) ->
      let manifest = match td.ptype_manifest with
      | None -> Doc.nil
      | Some(typ) -> Doc.concat [
          Doc.concat [Doc.space; Doc.text equalSign; Doc.space];
          printTypExpr typ cmtTbl;
        ]
      in
      Doc.concat [
        manifest;
        Doc.concat [Doc.space; Doc.text equalSign];
        printConstructorDeclarations ~privateFlag:td.ptype_private cds cmtTbl;
      ]
    in
    let constraints = printTypeDefinitionConstraints td.ptype_cstrs in
    Doc.group (
      Doc.concat [
        attrs;
        prefix;
        typeName;
        typeParams;
        manifestAndKind;
        constraints;
      ]
    )

  and printTypeDefinitionConstraints cstrs =
    match cstrs with
    | [] -> Doc.nil
    | cstrs -> Doc.indent (
        Doc.group (
          Doc.concat [
            Doc.line;
            Doc.group(
              Doc.join ~sep:Doc.line (
                List.map printTypeDefinitionConstraint cstrs
              )
            )
          ]
        )
      )

  and printTypeDefinitionConstraint ((typ1, typ2, _loc ): Parsetree.core_type * Parsetree.core_type * Location.t) =
    Doc.concat [
      Doc.text "constraint ";
      printTypExpr typ1 CommentTable.empty;
      Doc.text " = ";
      printTypExpr typ2 CommentTable.empty;
    ]

  and printPrivateFlag (flag : Asttypes.private_flag) = match flag with
    | Private -> Doc.text "private "
    | Public -> Doc.nil

  and printTypeParams typeParams cmtTbl =
    match typeParams with
    | [] -> Doc.nil
    | typeParams ->
      Doc.group (
        Doc.concat [
          Doc.lessThan;
          Doc.indent (
            Doc.concat [
              Doc.softLine;
              Doc.join ~sep:(Doc.concat [Doc.comma; Doc.line]) (
                List.map (fun typeParam ->
                  let doc = printTypeParam typeParam cmtTbl in
                  printComments doc cmtTbl (fst typeParam).Parsetree.ptyp_loc
                ) typeParams
              )
            ]
          );
          Doc.trailingComma;
          Doc.softLine;
          Doc.greaterThan;
        ]
      )

  and printTypeParam (param : (Parsetree.core_type * Asttypes.variance)) cmtTbl =
    let (typ, variance) = param in
    let printedVariance = match variance with
    | Covariant -> Doc.text "+"
    | Contravariant -> Doc.text "-"
    | Invariant -> Doc.nil
    in
    Doc.concat [
      printedVariance;
      printTypExpr typ cmtTbl
    ]

  and printRecordDeclaration (lds: Parsetree.label_declaration list) cmtTbl =
    let forceBreak = match (lds, List.rev lds) with
    | (first::_, last::_) ->
       first.pld_loc.loc_start.pos_lnum < last.pld_loc.loc_end.pos_lnum
    | _ -> false
    in
    Doc.breakableGroup ~forceBreak (
      Doc.concat [
        Doc.lbrace;
        Doc.indent (
          Doc.concat [
            Doc.softLine;
            Doc.join ~sep:(Doc.concat [Doc.comma; Doc.line])
              (List.map (fun ld ->
                let doc = printLabelDeclaration ld cmtTbl in
                printComments doc cmtTbl ld.Parsetree.pld_loc
              ) lds)
          ]
        );
        Doc.trailingComma;
        Doc.softLine;
        Doc.rbrace;
      ]
    )

  and printConstructorDeclarations
    ~privateFlag (cds: Parsetree.constructor_declaration list) cmtTbl
  =
    let forceBreak = match (cds, List.rev cds) with
    | (first::_, last::_) ->
       first.pcd_loc.loc_start.pos_lnum < last.pcd_loc.loc_end.pos_lnum
    | _ -> false
    in
    let privateFlag = match privateFlag with
    | Asttypes.Private -> Doc.concat [
        Doc.text "private";
        Doc.line;
      ]
    | Public -> Doc.nil
    in
    let rows =
      printListi
        ~getLoc:(fun cd -> cd.Parsetree.pcd_loc)
        ~nodes:cds
        ~print:(fun cd cmtTbl i ->
          let doc = printConstructorDeclaration2 i cd cmtTbl in
          printComments doc cmtTbl cd.Parsetree.pcd_loc
        )
        ~forceBreak
        cmtTbl
    in
    Doc.breakableGroup ~forceBreak (
      Doc.indent (
        Doc.concat [
          Doc.line;
          privateFlag;
          rows;
        ]
      )
    )

  and printConstructorDeclaration2 i (cd : Parsetree.constructor_declaration) cmtTbl =
    let attrs = printAttributes cd.pcd_attributes in
    let bar = if i > 0 then Doc.text "| "
    else Doc.ifBreaks (Doc.text "| ") Doc.nil
    in
    let constrName =
      let doc = Doc.text cd.pcd_name.txt in
      printComments doc cmtTbl cd.pcd_name.loc
    in
    let constrArgs = printConstructorArguments ~indent:true cd.pcd_args cmtTbl in
    let gadt = match cd.pcd_res with
    | None -> Doc.nil
    | Some(typ) -> Doc.indent (
        Doc.concat [
          Doc.text ": ";
          printTypExpr typ cmtTbl;
        ]
      )
    in
    Doc.concat [
      bar;
      Doc.group (
        Doc.concat [
          attrs; (* TODO: fix parsing of attributes, so when can print them above the bar? *)
          constrName;
          constrArgs;
          gadt;
        ]
      )
    ]

  and printConstructorArguments ~indent (cdArgs : Parsetree.constructor_arguments) cmtTbl =
    match cdArgs with
    | Pcstr_tuple [] -> Doc.nil
    | Pcstr_tuple types ->
      let args = Doc.concat [
        Doc.lparen;
          Doc.indent (
            Doc.concat [
            Doc.softLine;
            Doc.join ~sep:(Doc.concat [Doc.comma; Doc.line]) (
              List.map (fun typexpr ->
                printTypExpr typexpr cmtTbl
              ) types
            )
          ]
        );
        Doc.trailingComma;
        Doc.softLine;
        Doc.rparen;
      ] in
      Doc.group (
        if indent then Doc.indent args else args
      )
    | Pcstr_record lds ->
      let args = Doc.concat [
        Doc.lparen;
        (* manually inline the printRecordDeclaration, gives better layout *)
        Doc.lbrace;
        Doc.indent (
          Doc.concat [
            Doc.softLine;
            Doc.join ~sep:(Doc.concat [Doc.comma; Doc.line])
              (List.map (fun ld ->
                let doc = printLabelDeclaration ld cmtTbl in
                printComments doc cmtTbl ld.Parsetree.pld_loc
              ) lds)
          ]
        );
        Doc.trailingComma;
        Doc.softLine;
        Doc.rbrace;
        Doc.rparen;
      ] in
      if indent then Doc.indent args else args

  and printLabelDeclaration (ld : Parsetree.label_declaration) cmtTbl =
    let attrs = printAttributes ~loc:ld.pld_name.loc ld.pld_attributes in
    let mutableFlag = match ld.pld_mutable with
    | Mutable -> Doc.text "mutable "
    | Immutable -> Doc.nil
    in
    let name =
      let doc = printIdentLike ld.pld_name.txt in
      printComments doc cmtTbl ld.pld_name.loc
    in
    Doc.group (
      Doc.concat [
        attrs;
        mutableFlag;
        name;
        Doc.text ": ";
        printTypExpr ld.pld_type cmtTbl;
      ]
    )

  and printTypExpr (typExpr : Parsetree.core_type) cmtTbl =
    let renderedType = match typExpr.ptyp_desc with
    | Ptyp_any -> Doc.text "_"
    | Ptyp_var var -> Doc.text ("'" ^ var)
    | Ptyp_extension(extension) ->
      printExtensionWithComments extension cmtTbl
    | Ptyp_alias(typ, alias) ->
      let typ =
        (* Technically type t = (string, float) => unit as 'x, doesn't require
         * parens around the arrow expression. This is very confusing though.
         * Is the "as" part of "unit" or "(string, float) => unit". By printing
         * parens we guide the user towards its meaning.*)
        let needsParens = match typ.ptyp_desc with
        | Ptyp_arrow _ -> true
        | _ -> false
        in
        let doc = printTypExpr typ cmtTbl in
        if needsParens then
          Doc.concat [Doc.lparen; doc; Doc.rparen]
        else
          doc
      in
      Doc.concat [typ; Doc.text " as "; Doc.text ("'" ^ alias)]
    | Ptyp_constr({txt = Longident.Ldot(Longident.Lident "Js", "t")}, [typ]) ->
      let bsObject = printTypExpr typ cmtTbl in
      begin match typExpr.ptyp_attributes with
      | [] -> bsObject
      | attrs ->
        Doc.concat [
          Doc.group (
            Doc.join ~sep:Doc.line (List.map printAttribute attrs)
          );
          Doc.space;
          printTypExpr typ cmtTbl;
        ]
      end
    | Ptyp_constr(longidentLoc, [{ ptyp_desc = Parsetree.Ptyp_tuple tuple }]) ->
      let constrName = printLongidentLocation longidentLoc cmtTbl in
      Doc.group(
        Doc.concat([
          constrName;
          Doc.lessThan;
          printTupleType ~inline:true tuple cmtTbl;
          Doc.greaterThan;
        ])
      )
    | Ptyp_constr(longidentLoc, constrArgs) ->
      let constrName = printLongidentLocation longidentLoc cmtTbl in
      begin match constrArgs with
      | [] -> constrName
      | [{
          Parsetree.ptyp_desc =
            Ptyp_constr({txt = Longident.Ldot(Longident.Lident "Js", "t")},
          [{ptyp_desc = Ptyp_object (fields, openFlag)}])
        }] ->
        Doc.concat([
          constrName;
          Doc.lessThan;
          printBsObjectSugar ~inline:true fields openFlag cmtTbl;
          Doc.greaterThan;
        ])
      | args -> Doc.group(
        Doc.concat([
          constrName;
          Doc.lessThan;
          Doc.indent (
            Doc.concat [
              Doc.softLine;
              Doc.join ~sep:(Doc.concat [Doc.comma; Doc.line]) (
                List.map
                  (fun typexpr -> printTypExpr typexpr cmtTbl)
                  constrArgs
              )
            ]
          );
          Doc.trailingComma;
          Doc.softLine;
          Doc.greaterThan;
        ])
      )
      end
    | Ptyp_arrow _ ->
      let (attrsBefore, args, returnType) = ParsetreeViewer.arrowType typExpr in
      let returnTypeNeedsParens = match returnType.ptyp_desc with
      | Ptyp_alias _ -> true
      | _ -> false
      in
      let returnDoc =
        let doc = printTypExpr returnType cmtTbl in
        if returnTypeNeedsParens then
          Doc.concat [Doc.lparen; doc; Doc.rparen]
        else doc
      in
      let (isUncurried, attrs) =
        ParsetreeViewer.processUncurriedAttribute attrsBefore
      in
      begin match args with
      | [] -> Doc.nil
      | [([], Nolabel, n)] when not isUncurried ->
          let hasAttrsBefore = not (attrs = []) in
          let attrs = if hasAttrsBefore then
            Doc.concat [
              Doc.join ~sep:Doc.line (List.map printAttribute attrsBefore);
              Doc.space;
            ]
          else Doc.nil
          in
          let typDoc =
            let doc = printTypExpr n cmtTbl in
            match n.ptyp_desc with
            | Ptyp_arrow _ -> addParens doc
            | _ -> doc
          in
          Doc.group (
            Doc.concat [
              Doc.group attrs;
              Doc.group (
                if hasAttrsBefore then
                  Doc.concat [
                    Doc.lparen;
                    Doc.indent (
                      Doc.concat [
                        Doc.softLine;
                        typDoc;
                        Doc.text " => ";
                        returnDoc;
                      ]
                    );
                    Doc.softLine;
                    Doc.rparen
                  ]
                else
                Doc.concat [
                  typDoc;
                  Doc.text " => ";
                  returnDoc;
                ]
              )
            ]
          )
      | args ->
        let attrs = match attrs with
        | [] -> Doc.nil
        | attrs -> Doc.concat [
            Doc.join ~sep:Doc.line (List.map printAttribute attrs);
            Doc.space;
          ]
        in
        let renderedArgs = Doc.concat [
          attrs;
          Doc.text "(";
          Doc.indent (
            Doc.concat [
              Doc.softLine;
              if isUncurried then Doc.concat [Doc.dot; Doc.space] else Doc.nil;
              Doc.join ~sep:(Doc.concat [Doc.comma; Doc.line]) (
                List.map (fun tp -> printTypeParameter tp cmtTbl) args
              )
            ]
          );
          Doc.trailingComma;
          Doc.softLine;
          Doc.text ")";
        ] in
        Doc.group (
          Doc.concat [
            renderedArgs;
            Doc.text " => ";
            returnDoc;
          ]
        )
      end
    | Ptyp_tuple types -> printTupleType ~inline:false types cmtTbl
    | Ptyp_object (fields, openFlag) ->
      printBsObjectSugar ~inline:false fields openFlag cmtTbl
    | Ptyp_poly(stringLocs, typ) ->
      Doc.concat [
        Doc.join ~sep:Doc.space (List.map (fun {Location.txt; loc} ->
          let doc = Doc.concat [Doc.text "'"; Doc.text txt] in
          printComments doc cmtTbl loc
          ) stringLocs);
        Doc.dot;
        Doc.space;
        printTypExpr typ cmtTbl
      ]
    | Ptyp_package packageType ->
      printPackageType ~printModuleKeywordAndParens:true packageType cmtTbl
    | Ptyp_class _ -> failwith "classes are not supported in types"
    | Ptyp_variant _ -> failwith "Polymorphic variants currently not supported"
    in
    let shouldPrintItsOwnAttributes = match typExpr.ptyp_desc with
    | Ptyp_arrow _ (* es6 arrow types print their own attributes *)
    | Ptyp_constr({txt = Longident.Ldot(Longident.Lident "Js", "t")}, _) -> true
    | _ -> false
    in
    let doc = begin match typExpr.ptyp_attributes with
    | _::_ as attrs when not shouldPrintItsOwnAttributes ->
      Doc.group (
        Doc.concat [
          printAttributes attrs;
          renderedType;
        ]
      )
    | _ -> renderedType
    end
    in
    printComments doc cmtTbl typExpr.ptyp_loc

  and printBsObjectSugar ~inline fields openFlag cmtTbl =
    let flag = match openFlag with
    | Asttypes.Closed -> Doc.nil
    | Open -> Doc.dotdot
    in
    let doc = Doc.concat [
      Doc.lbrace;
      flag;
      Doc.indent (
        Doc.concat [
          Doc.softLine;
          Doc.join ~sep:(Doc.concat [Doc.comma; Doc.line]) (
            List.map (fun field -> printObjectField field cmtTbl) fields
          )
        ]
      );
      Doc.trailingComma;
      Doc.softLine;
      Doc.rbrace;
    ] in
    if inline then doc else Doc.group doc

  and printTupleType ~inline (types: Parsetree.core_type list) cmtTbl =
    let tuple = Doc.concat([
      Doc.lparen;
      Doc.indent (
        Doc.concat([
          Doc.softLine;
          Doc.join ~sep:(Doc.concat [Doc.comma; Doc.line]) (
            List.map (fun typexpr -> printTypExpr typexpr cmtTbl) types
          )
        ])
      );
      Doc.trailingComma;
      Doc.softLine;
      Doc.rparen;
    ])
    in
    if inline == false then Doc.group(tuple) else tuple

  and printObjectField (field : Parsetree.object_field) cmtTbl =
    match field with
    | Otag (labelLoc, attrs, typ) ->
      let lbl =
        let doc = Doc.text ("\"" ^ labelLoc.txt ^ "\"") in
        printComments doc cmtTbl labelLoc.loc
      in
      let doc = Doc.concat [
        lbl;
        Doc.text ": ";
        printTypExpr typ cmtTbl;
      ] in
      let cmtLoc = {labelLoc.loc with loc_end = typ.ptyp_loc.loc_end} in
      printComments doc cmtTbl cmtLoc
    | _ -> Doc.nil

  (* es6 arrow type arg
   * type t = (~foo: string, ~bar: float=?, unit) => unit
   * i.e. ~foo: string, ~bar: float *)
  and printTypeParameter (attrs, lbl, typ) cmtTbl =
    let (isUncurried, attrs) = ParsetreeViewer.processUncurriedAttribute attrs in
    let uncurried = if isUncurried then Doc.concat [Doc.dot; Doc.space] else Doc.nil in
    let attrs = match attrs with
    | [] -> Doc.nil
    | attrs -> Doc.concat [
      Doc.join ~sep:Doc.line (List.map printAttribute attrs);
      Doc.line;
    ] in
    let label = match lbl with
    | Asttypes.Nolabel -> Doc.nil
    | Labelled lbl -> Doc.text ("~" ^ lbl ^ ": ")
    | Optional lbl -> Doc.text ("~" ^ lbl ^ ": ")
    in
    let optionalIndicator = match lbl with
    | Asttypes.Nolabel
    | Labelled _ -> Doc.nil
    | Optional lbl -> Doc.text "=?"
    in
    let doc = Doc.group (
      Doc.concat [
        uncurried;
        attrs;
        label;
        printTypExpr typ cmtTbl;
        optionalIndicator;
      ]
    ) in
    printComments doc cmtTbl typ.ptyp_loc

  and printValueBinding ~recFlag vb cmtTbl i =
    let vb = ParsetreeViewer.unwrapMangledValueBinding vb in
    let (hasGenType, attrs) = ParsetreeViewer.splitGenTypeAttr vb.pvb_attributes in
    let attrs = printAttributes ~loc:vb.pvb_pat.ppat_loc attrs in
		let header =
      if i == 0 then
        Doc.concat [
          if hasGenType then Doc.text "export " else Doc.text "let ";
          recFlag
      ] else
        Doc.concat [
          Doc.text "and ";
          if hasGenType then Doc.text "export " else Doc.nil
        ]
		in
    let (optBraces, expr) = ParsetreeViewer.processBracesAttr vb.pvb_expr in
    let printedExpr =
      let doc = printExpressionWithComments vb.pvb_expr cmtTbl in
      match Parens.expr vb.pvb_expr with
      | Parens.Parenthesized -> addParens doc
      | Braced braces  -> printBraces doc expr braces
      | Nothing -> doc
    in
    if ParsetreeViewer.isPipeExpr vb.pvb_expr then
      Doc.customLayout [
        Doc.group (
          Doc.concat [
            attrs;
            header;
            printPattern vb.pvb_pat cmtTbl;
            Doc.text " =";
            Doc.space;
            printedExpr;
          ]
        );
        Doc.group (
          Doc.concat [
            attrs;
            header;
            printPattern vb.pvb_pat cmtTbl;
            Doc.text " =";
            Doc.indent (
              Doc.concat [
              Doc.line;
              printedExpr;
              ]
            )
          ]
        );
      ]
		else
      let shouldIndent =
        match optBraces with
        | Some _ -> false
        | _ ->
          ParsetreeViewer.isBinaryExpression expr ||
          (match vb.pvb_expr with
          | {
              pexp_attributes = [({Location.txt="ns.ternary"}, _)];
              pexp_desc = Pexp_ifthenelse (ifExpr, _, _)
            }  ->
            ParsetreeViewer.isBinaryExpression ifExpr || ParsetreeViewer.hasAttributes ifExpr.pexp_attributes
        | { pexp_desc = Pexp_newtype _} -> false
        | e ->
            ParsetreeViewer.hasAttributes e.pexp_attributes ||
            ParsetreeViewer.isArrayAccess e
          )
      in
      Doc.group (
        Doc.concat [
          attrs;
          header;
          printPattern vb.pvb_pat cmtTbl;
          Doc.text " =";
          if shouldIndent then
            Doc.indent (
              Doc.concat [
                Doc.line;
                printedExpr;
              ]
            )
          else
            Doc.concat [
              Doc.space;
              printedExpr;
            ]
        ]
      )

  and printPackageType ~printModuleKeywordAndParens (packageType: Parsetree.package_type) cmtTbl =
    let doc = match packageType with
    | (longidentLoc, []) -> Doc.group(
        Doc.concat [
          printLongidentLocation longidentLoc cmtTbl;
        ]
      )
    | (longidentLoc, packageConstraints) -> Doc.group(
        Doc.concat [
          printLongidentLocation longidentLoc cmtTbl;
          printPackageConstraints packageConstraints cmtTbl;
          Doc.softLine;
        ]
      )
    in
    if printModuleKeywordAndParens then
      Doc.concat[
        Doc.text "module(";
        doc;
        Doc.rparen
      ]
    else
      doc

  and printPackageConstraints packageConstraints cmtTbl  =
    Doc.concat [
      Doc.text " with";
      Doc.indent (
        Doc.concat [
          Doc.line;
          Doc.join ~sep:Doc.line (
            List.mapi (fun i pc ->
              let (longident, typexpr) = pc in
              let cmtLoc = {longident.Asttypes.loc with
                loc_end = typexpr.Parsetree.ptyp_loc.loc_end
              } in
              let doc = printPackageConstraint i cmtTbl pc in
              printComments doc cmtTbl cmtLoc
            ) packageConstraints
          )
        ]
      )
    ]

  and printPackageConstraint i cmtTbl (longidentLoc, typ) =
    let prefix = if i == 0 then Doc.text "type " else Doc.text "and type " in
    Doc.concat [
      prefix;
      printLongidentLocation longidentLoc cmtTbl;
      Doc.text " = ";
      printTypExpr typ cmtTbl;
    ]

  and printExtensionWithComments (stringLoc, payload) cmtTbl =
    let extName =
      let doc = Doc.text ("%" ^ stringLoc.Location.txt) in
      printComments doc cmtTbl stringLoc.Location.loc
    in
    match payload with
    | Parsetree.PStr [{pstr_desc = Pstr_eval (expr, attrs)}] ->
      let exprDoc = printExpressionWithComments expr cmtTbl in
      let needsParens = match attrs with | [] -> false | _ -> true in
      Doc.group (
        Doc.concat [
          extName;
          addParens (
            Doc.concat [
              printAttributes attrs;
              if needsParens then addParens exprDoc else exprDoc;
            ]
          )
        ]
      )
    | _ -> extName

  and printPattern (p : Parsetree.pattern) cmtTbl =
    let patternWithoutAttributes = match p.ppat_desc with
    | Ppat_any -> Doc.text "_"
    | Ppat_var var -> Doc.text var.txt
    | Ppat_constant c -> printConstant c
    | Ppat_tuple patterns ->
      Doc.group(
        Doc.concat([
          Doc.lparen;
          Doc.indent (
            Doc.concat([
              Doc.softLine;
              Doc.join ~sep:(Doc.concat [Doc.text ","; Doc.line])
                (List.map (fun pat ->
                  printPattern pat cmtTbl) patterns)
            ])
          );
          Doc.trailingComma;
          Doc.softLine;
          Doc.rparen
        ])
      )
    | Ppat_array [] ->
      Doc.concat [
        Doc.lbracket;
        printCommentsInside cmtTbl p.ppat_loc;
        Doc.rbracket;
      ]
    | Ppat_array patterns ->
      Doc.group(
        Doc.concat([
          Doc.text "[";
          Doc.indent (
            Doc.concat([
              Doc.softLine;
              Doc.join ~sep:(Doc.concat [Doc.text ","; Doc.line])
                (List.map (fun pat ->
                  printPattern pat cmtTbl) patterns)
            ])
          );
          Doc.trailingComma;
          Doc.softLine;
          Doc.text "]";
        ])
      )
    | Ppat_construct({txt = Longident.Lident "[]"}, _) ->
      Doc.concat [
        Doc.text "list[";
        printCommentsInside cmtTbl p.ppat_loc;
        Doc.rbracket;
      ]
    | Ppat_construct({txt = Longident.Lident "::"}, _) ->
      let (patterns, tail) = ParsetreeViewer.collectPatternsFromListConstruct [] p in
      let shouldHug = match (patterns, tail) with
      | ([pat],
        {ppat_desc = Ppat_construct({txt = Longident.Lident "[]"}, _)}) when ParsetreeViewer.isHuggablePattern pat -> true
      | _ -> false
      in
      let children = Doc.concat([
        if shouldHug then Doc.nil else Doc.softLine;
        Doc.join ~sep:(Doc.concat [Doc.text ","; Doc.line])
          (List.map (fun pat ->
            printPattern pat cmtTbl) patterns);
        begin match tail.Parsetree.ppat_desc with
        | Ppat_construct({txt = Longident.Lident "[]"}, _) -> Doc.nil
        | _ ->
          let doc = Doc.concat [Doc.text "..."; printPattern tail cmtTbl] in
          let tail = printComments doc cmtTbl tail.ppat_loc in
          Doc.concat([Doc.text ","; Doc.line; tail])
        end;
      ]) in
      Doc.group(
        Doc.concat([
          Doc.text "list[";
          if shouldHug then children else Doc.concat [
            Doc.indent children;
            Doc.ifBreaks (Doc.text ",") Doc.nil;
            Doc.softLine;
          ];
          Doc.rbracket;
        ])
      )
    | Ppat_construct(constrName, constructorArgs) ->
      let constrName = printLongident constrName.txt in
      let argsDoc = match constructorArgs with
      | None -> Doc.nil
      | Some({ppat_desc = Ppat_construct ({txt = Longident.Lident "()"}, _)}) ->
        Doc.text "()"
      | Some({ppat_desc = Ppat_tuple []; ppat_loc = loc}) ->
        Doc.concat [
          Doc.lparen;
          Doc.softLine;
          printCommentsInside cmtTbl loc;
          Doc.rparen;
        ]
      (* Some((1, 2) *)
      | Some({ppat_desc = Ppat_tuple [{ppat_desc = Ppat_tuple _} as arg]}) ->
        Doc.concat [
          Doc.lparen;
          printPattern arg cmtTbl;
          Doc.rparen;
        ]
      | Some({ppat_desc = Ppat_tuple patterns}) ->
        Doc.concat [
          Doc.lparen;
          Doc.indent (
            Doc.concat [
              Doc.softLine;
              Doc.join ~sep:(Doc.concat [Doc.comma; Doc.line]) (
                List.map (fun pat -> printPattern pat cmtTbl) patterns
              );
            ]
          );
          Doc.trailingComma;
          Doc.softLine;
          Doc.rparen;
        ]
      | Some(arg) ->
        let argDoc = printPattern arg cmtTbl in
        let shouldHug = ParsetreeViewer.isHuggablePattern arg in
        Doc.concat [
          Doc.lparen;
          if shouldHug then argDoc
          else Doc.concat [
            Doc.indent (
              Doc.concat [
                Doc.softLine;
                argDoc;
              ]
            );
            Doc.trailingComma;
            Doc.softLine;
          ];
          Doc.rparen;

        ]
      in
      Doc.group(Doc.concat [constrName; argsDoc])
    | Ppat_record(rows, openFlag) ->
        Doc.group(
          Doc.concat([
            Doc.lbrace;
            Doc.indent (
              Doc.concat [
                Doc.softLine;
                Doc.join ~sep:(Doc.concat [Doc.text ","; Doc.line])
                  (List.map (fun row -> printPatternRecordRow row cmtTbl) rows);
                begin match openFlag with
                | Open -> Doc.concat [Doc.text ","; Doc.line; Doc.text "_"]
                | Closed -> Doc.nil
                end;
              ]
            );
            Doc.ifBreaks (Doc.text ",") Doc.nil;
            Doc.softLine;
            Doc.rbrace;
          ])
        )

    | Ppat_exception p ->
        let needsParens = match p.ppat_desc with
        | Ppat_or (_, _) | Ppat_alias (_, _) -> true
        | _ -> false
        in
        let pat =
          let p = printPattern p cmtTbl in
          if needsParens then
            Doc.concat [Doc.text "("; p; Doc.text ")"]
          else
            p
        in
        Doc.group (
          Doc.concat [Doc.text "exception"; Doc.line; pat]
        )
    | Ppat_or _ ->
      (* Blue | Red | Green -> [Blue; Red; Green] *)
      let orChain = ParsetreeViewer.collectOrPatternChain p in
      let docs = List.mapi (fun i pat ->
        let patternDoc = printPattern pat cmtTbl in
        Doc.concat [
          if i == 0 then Doc.nil else Doc.concat [Doc.line; Doc.text "| "];
          match pat.ppat_desc with
          (* (Blue | Red) | (Green | Black) | White *)
          | Ppat_or _ -> addParens patternDoc
          | _ -> patternDoc
        ]
      ) orChain in
      Doc.group (Doc.concat docs)
    | Ppat_extension ext ->
      printExtensionWithComments ext cmtTbl
    | Ppat_lazy p ->
      let needsParens = match p.ppat_desc with
      | Ppat_or (_, _) | Ppat_alias (_, _) -> true
      | _ -> false
      in
      let pat =
        let p = printPattern p cmtTbl in
        if needsParens then
          Doc.concat [Doc.text "("; p; Doc.text ")"]
        else
          p
      in
      Doc.concat [Doc.text "lazy "; pat]
    | Ppat_alias (p, aliasLoc) ->
      let needsParens = match p.ppat_desc with
      | Ppat_or (_, _) | Ppat_alias (_, _) -> true
      | _ -> false
      in
      let renderedPattern =
        let p = printPattern p cmtTbl in
        if needsParens then
          Doc.concat [Doc.text "("; p; Doc.text ")"]
        else
          p
      in
      Doc.concat([
        renderedPattern;
        Doc.text " as ";
        printStringLoc aliasLoc cmtTbl;
      ])

     (* Note: module(P : S) is represented as *)
     (* Ppat_constraint(Ppat_unpack, Ptyp_package) *)
    | Ppat_constraint ({ppat_desc = Ppat_unpack stringLoc}, {ptyp_desc = Ptyp_package packageType; ptyp_loc}) ->
        Doc.concat [
          Doc.text "module(";
          printComments (Doc.text stringLoc.txt) cmtTbl stringLoc.loc;
          Doc.text ": ";
          printComments
            (printPackageType ~printModuleKeywordAndParens:false packageType cmtTbl)
            cmtTbl
            ptyp_loc;
          Doc.rparen;
        ]
    | Ppat_constraint (pattern, typ) ->
      Doc.concat [
        printPattern pattern cmtTbl;
        Doc.text ": ";
        printTypExpr typ cmtTbl;
      ]

     (* Note: module(P : S) is represented as *)
     (* Ppat_constraint(Ppat_unpack, Ptyp_package) *)
    | Ppat_unpack stringLoc ->
      Doc.concat [
        Doc.text "module(";
        printComments (Doc.text stringLoc.txt) cmtTbl stringLoc.loc;
        Doc.rparen;
      ]
    | Ppat_open _ | Ppat_interval (_, _) | Ppat_variant (_, _)| Ppat_type _->
      Doc.nil
    in
    let doc = match p.ppat_attributes with
    | [] -> patternWithoutAttributes
    | attrs ->
      Doc.group (
        Doc.concat [
          printAttributes attrs;
          patternWithoutAttributes;
        ]
      )
    in
    printComments doc cmtTbl p.ppat_loc

  and printPatternRecordRow row cmtTbl =
    match row with
    (* punned {x}*)
    | ({Location.txt=Longident.Lident ident} as longident,
       {Parsetree.ppat_desc=Ppat_var {txt;_}}) when ident = txt ->
        printLongidentLocation longident cmtTbl
    | (longident, pattern) ->
      let locForComments = {
        longident.loc with
        loc_end = pattern.Parsetree.ppat_loc.loc_end
      } in
      let doc = Doc.group (
        Doc.concat([
          printLongidentLocation longident cmtTbl;
          Doc.text ": ";
          Doc.indent(
            Doc.concat [
              Doc.softLine;
              printPattern pattern cmtTbl;
            ]
          )
        ])
      ) in
      printComments doc cmtTbl locForComments

  and printExpressionWithComments expr cmtTbl =
    let doc = printExpression expr cmtTbl in
    printComments doc cmtTbl expr.Parsetree.pexp_loc

  and printExpression (e : Parsetree.expression) cmtTbl =
    let printedExpression = match e.pexp_desc with
    | Parsetree.Pexp_constant c -> printConstant c
    | Pexp_construct _ when ParsetreeViewer.hasJsxAttribute e.pexp_attributes ->
      printJsxFragment e cmtTbl
    | Pexp_construct ({txt = Longident.Lident "()"}, _) -> Doc.text "()"
    | Pexp_construct ({txt = Longident.Lident "[]"}, _) ->
      Doc.concat [
        Doc.text "list[";
        printCommentsInside cmtTbl e.pexp_loc;
        Doc.rbracket;
      ]
    | Pexp_construct ({txt = Longident.Lident "::"}, _) ->
      let (expressions, spread) = ParsetreeViewer.collectListExpressions e in
      let spreadDoc = match spread with
      | Some(expr) -> Doc.concat [
          Doc.text ",";
          Doc.line;
          Doc.dotdotdot;
          let doc = printExpressionWithComments expr cmtTbl in
          match Parens.expr expr with
          | Parens.Parenthesized -> addParens doc
          | Braced braces -> printBraces doc expr braces
          | Nothing -> doc
        ]
      | None -> Doc.nil
      in
      Doc.group(
        Doc.concat([
          Doc.text "list[";
          Doc.indent (
            Doc.concat([
              Doc.softLine;
              Doc.join ~sep:(Doc.concat [Doc.text ","; Doc.line])
                (List.map
                  (fun expr ->
                    let doc = printExpressionWithComments expr cmtTbl in
                    match Parens.expr expr with
                    | Parens.Parenthesized -> addParens doc
                    | Braced braces -> printBraces doc expr braces
                    | Nothing -> doc
                  )
                  expressions);
              spreadDoc;
            ])
          );
          Doc.trailingComma;
          Doc.softLine;
          Doc.rbracket;
        ])
      )
    | Pexp_construct (longidentLoc, args) ->
      let constr = printLongidentLocation longidentLoc cmtTbl in
      let args = match args with
      | None -> Doc.nil
      | Some({pexp_desc = Pexp_construct ({txt = Longident.Lident "()"}, _)}) ->
        Doc.text "()"
      (* Some((1, 2) *)
      | Some({pexp_desc = Pexp_tuple [{pexp_desc = Pexp_tuple _} as arg]}) ->
        Doc.concat [
          Doc.lparen;
          (let doc = printExpressionWithComments arg cmtTbl in
          match Parens.expr arg with
          | Parens.Parenthesized -> addParens doc
          | Braced braces -> printBraces doc arg braces
          | Nothing -> doc);
          Doc.rparen;
        ]
      | Some({pexp_desc = Pexp_tuple args }) ->
        Doc.concat [
          Doc.lparen;
          Doc.indent (
            Doc.concat [
              Doc.softLine;
              Doc.join ~sep:(Doc.concat [Doc.comma; Doc.line]) (
                List.map
                  (fun expr ->
                    let doc = printExpressionWithComments expr cmtTbl in
                    match Parens.expr expr with
                    | Parens.Parenthesized -> addParens doc
                    | Braced braces -> printBraces doc expr braces
                    | Nothing -> doc)
                  args
              )
            ]
          );
          Doc.trailingComma;
          Doc.softLine;
          Doc.rparen;
        ]
      | Some(arg) ->
        let argDoc =
          let doc = printExpressionWithComments arg cmtTbl in
          match Parens.expr arg with
          | Parens.Parenthesized -> addParens doc
          | Braced braces -> printBraces doc arg braces
          | Nothing -> doc
        in
        let shouldHug = ParsetreeViewer.isHuggableExpression arg in
        Doc.concat [
          Doc.lparen;
          if shouldHug then argDoc
          else Doc.concat [
            Doc.indent (
              Doc.concat [
                Doc.softLine;
                argDoc;
              ]
            );
            Doc.trailingComma;
            Doc.softLine;
          ];
          Doc.rparen;
        ]
      in
      Doc.group(Doc.concat [constr; args])
    | Pexp_ident(longident) ->
      printLongidentLocation longident cmtTbl
    | Pexp_tuple exprs ->
      Doc.group(
        Doc.concat([
          Doc.lparen;
          Doc.indent (
            Doc.concat([
              Doc.softLine;
              Doc.join ~sep:(Doc.concat [Doc.text ","; Doc.line])
                (List.map (fun expr ->
                  let doc = printExpressionWithComments expr cmtTbl in
                  match Parens.expr expr with
                  | Parens.Parenthesized -> addParens doc
                  | Braced braces -> printBraces doc expr braces
                  | Nothing -> doc)
                 exprs)
            ])
          );
          Doc.ifBreaks (Doc.text ",") Doc.nil;
          Doc.softLine;
          Doc.rparen;
        ])
      )
    | Pexp_array [] ->
      Doc.concat [
        Doc.lbracket;
        printCommentsInside cmtTbl e.pexp_loc;
        Doc.rbracket;
      ]
    | Pexp_array exprs ->
      Doc.group(
        Doc.concat([
          Doc.lbracket;
          Doc.indent (
            Doc.concat([
              Doc.softLine;
              Doc.join ~sep:(Doc.concat [Doc.text ","; Doc.line])
                (List.map (fun expr ->
                  let doc = printExpressionWithComments expr cmtTbl in
                  match Parens.expr expr with
                  | Parens.Parenthesized -> addParens doc
                  | Braced braces -> printBraces doc expr braces
                  | Nothing -> doc
                  ) exprs)
            ])
          );
          Doc.trailingComma;
          Doc.softLine;
          Doc.rbracket;
        ])
      )
    | Pexp_record (rows, spreadExpr) ->
      let spread = match spreadExpr with
      | None -> Doc.nil
      | Some expr -> Doc.concat [
          Doc.dotdotdot;
          (let doc = printExpressionWithComments expr cmtTbl in
          match Parens.expr expr with
          | Parens.Parenthesized -> addParens doc
          | Braced braces -> printBraces doc expr braces
          | Nothing -> doc);
          Doc.comma;
          Doc.line;
        ]
      in
      (* If the record is written over multiple lines, break automatically
       * `let x = {a: 1, b: 3}` -> same line, break when line-width exceeded
       * `let x = {
       *   a: 1,
       *   b: 2,
       *  }` -> record is written on multiple lines, break the group *)
      let forceBreak =
        e.pexp_loc.loc_start.pos_lnum < e.pexp_loc.loc_end.pos_lnum
      in
      Doc.breakableGroup ~forceBreak (
        Doc.concat([
          Doc.lbrace;
          Doc.indent (
            Doc.concat [
              Doc.softLine;
              spread;
              Doc.join ~sep:(Doc.concat [Doc.text ","; Doc.line])
                (List.map (fun row -> printRecordRow row cmtTbl) rows)
            ]
          );
          Doc.trailingComma;
          Doc.softLine;
          Doc.rbrace;
        ])
      )
    | Pexp_extension extension ->
      begin match extension with
      | (
          {txt = "bs.obj"},
          PStr [{
            pstr_loc = loc;
            pstr_desc = Pstr_eval({pexp_desc = Pexp_record (rows, _)}, [])
          }]
        ) ->
        (* If the object is written over multiple lines, break automatically
         * `let x = {"a": 1, "b": 3}` -> same line, break when line-width exceeded
         * `let x = {
         *   "a": 1,
         *   "b": 2,
         *  }` -> object is written on multiple lines, break the group *)
        let forceBreak =
          loc.loc_start.pos_lnum < loc.loc_end.pos_lnum
        in
        Doc.breakableGroup ~forceBreak (
          Doc.concat([
            Doc.lbrace;
            Doc.indent (
              Doc.concat [
                Doc.softLine;
                Doc.join ~sep:(Doc.concat [Doc.text ","; Doc.line])
                  (List.map (fun row -> printBsObjectRow row cmtTbl) rows)
              ]
            );
            Doc.trailingComma;
            Doc.softLine;
            Doc.rbrace;
          ])
        )
      | extension ->
        printExtensionWithComments extension cmtTbl
      end
    | Pexp_apply _ ->
      if ParsetreeViewer.isUnaryExpression e then
        printUnaryExpression e cmtTbl
      else if ParsetreeViewer.isTemplateLiteral e then
        printTemplateLiteral e cmtTbl
      else if ParsetreeViewer.isBinaryExpression e then
        printBinaryExpression e cmtTbl
      else
        printPexpApply e cmtTbl
    | Pexp_unreachable -> Doc.dot
    | Pexp_field (expr, longidentLoc) ->
      let lhs =
        let doc = printExpressionWithComments expr cmtTbl in
        match Parens.fieldExpr expr with
        | Parens.Parenthesized -> addParens doc
        | Braced braces  -> printBraces doc expr braces
        | Nothing -> doc
      in
      Doc.concat [
        lhs;
        Doc.dot;
        printLongidentLocation longidentLoc cmtTbl;
      ]
    | Pexp_setfield (expr1, longidentLoc, expr2) ->
      printSetFieldExpr e.pexp_attributes expr1 longidentLoc expr2 e.pexp_loc cmtTbl
    | Pexp_ifthenelse (ifExpr, thenExpr, elseExpr) ->
      if ParsetreeViewer.isTernaryExpr e then
        let (parts, alternate) = ParsetreeViewer.collectTernaryParts e in
        let ternaryDoc = match parts with
        | (condition1, consequent1)::rest ->
          Doc.group (Doc.concat [
            printTernaryOperand condition1 cmtTbl;
            Doc.indent (
              Doc.concat [
                Doc.line;
                Doc.indent (
                  Doc.concat [
                    Doc.text "? ";
                    printTernaryOperand consequent1 cmtTbl
                  ]
                );
                Doc.concat (
                  List.map (fun (condition, consequent) ->
                    Doc.concat [
                      Doc.line;
                      Doc.text ": ";
                      printTernaryOperand condition cmtTbl;
                      Doc.line;
                      Doc.text "? ";
                      printTernaryOperand consequent cmtTbl;
                    ]
                  ) rest
                );
                Doc.line;
                Doc.text ": ";
                Doc.indent (printTernaryOperand alternate cmtTbl);
              ]
            )
          ])
        | _ -> Doc.nil
        in
        let attrs = ParsetreeViewer.filterTernaryAttributes e.pexp_attributes in
        let needsParens = match ParsetreeViewer.filterParsingAttrs attrs with
        | [] -> false | _ -> true
        in
        Doc.concat [
          printAttributes attrs;
          if needsParens then addParens ternaryDoc else ternaryDoc;
        ]
      else
      let (ifs, elseExpr) = ParsetreeViewer.collectIfExpressions e in
      let ifDocs = Doc.join ~sep:Doc.space (
        List.mapi (fun i (ifExpr, thenExpr) ->
          let ifTxt = if i > 0 then Doc.text "else if " else  Doc.text "if " in
          let condition =
            if ParsetreeViewer.isBlockExpr ifExpr then
              printExpressionBlock ~braces:true ifExpr cmtTbl
            else
              let doc = printExpressionWithComments ifExpr cmtTbl in
              match Parens.expr ifExpr with
              | Parens.Parenthesized -> addParens doc
              | Braced braces -> printBraces doc ifExpr braces
              | Nothing -> Doc.ifBreaks (addParens doc) (Doc.group doc)
          in
          Doc.concat [
            ifTxt;
            Doc.group (condition);
            Doc.space;
            printExpressionBlock ~braces:true thenExpr cmtTbl;
          ]
        ) ifs
      ) in
      let elseDoc = match elseExpr with
      | None -> Doc.nil
      | Some expr -> Doc.concat [
          Doc.text " else ";
          printExpressionBlock ~braces:true expr cmtTbl;
        ]
      in
      Doc.concat [
        printAttributes e.pexp_attributes;
        ifDocs;
        elseDoc;
      ]
    | Pexp_while (expr1, expr2) ->
      let condition =
        let doc = printExpressionWithComments expr1 cmtTbl in
        match Parens.expr expr1 with
        | Parens.Parenthesized -> addParens doc
        | Braced braces  -> printBraces doc expr1 braces
        | Nothing -> doc
      in
      Doc.breakableGroup ~forceBreak:true (
        Doc.concat [
          Doc.text "while ";
          if ParsetreeViewer.isBlockExpr expr1 then
            condition
          else
            Doc.group (
              Doc.ifBreaks (addParens condition) condition
            );
          Doc.space;
          printExpressionBlock ~braces:true expr2 cmtTbl;
        ]
      )
    | Pexp_for (pattern, fromExpr, toExpr, directionFlag, body) ->
      Doc.breakableGroup ~forceBreak:true (
        Doc.concat [
          Doc.text "for ";
          printPattern pattern cmtTbl;
          Doc.text " in ";
          (let doc = printExpressionWithComments fromExpr cmtTbl in
          match Parens.expr fromExpr with
          | Parens.Parenthesized -> addParens doc
          | Braced braces -> printBraces doc fromExpr braces
          | Nothing -> doc);
          printDirectionFlag directionFlag;
          (let doc = printExpressionWithComments toExpr cmtTbl in
          match Parens.expr toExpr with
          | Parens.Parenthesized -> addParens doc
          | Braced braces -> printBraces doc toExpr braces
          | Nothing -> doc);
          Doc.space;
          printExpressionBlock ~braces:true body cmtTbl;
        ]
      )
    | Pexp_constraint(
        {pexp_desc = Pexp_pack modExpr},
        {ptyp_desc = Ptyp_package packageType; ptyp_loc}
      ) ->
      Doc.group (
        Doc.concat [
          Doc.text "module(";
          Doc.indent (
            Doc.concat [
              Doc.softLine;
              printModExpr modExpr cmtTbl;
              Doc.text ": ";
              printComments
                (printPackageType ~printModuleKeywordAndParens:false packageType cmtTbl)
                cmtTbl
                ptyp_loc
            ]
          );
          Doc.softLine;
          Doc.rparen;
        ]
      )

    | Pexp_constraint (expr, typ) ->
      let exprDoc =
        let doc = printExpressionWithComments expr cmtTbl in
        match Parens.expr expr with
        | Parens.Parenthesized -> addParens doc
        | Braced braces  -> printBraces doc expr braces
        | Nothing -> doc
      in
      Doc.concat [
        exprDoc;
        Doc.text ": ";
        printTypExpr typ cmtTbl;
      ]
    | Pexp_letmodule ({txt = modName}, modExpr, expr) ->
      printExpressionBlock ~braces:true e cmtTbl
    | Pexp_letexception (extensionConstructor, expr) ->
      printExpressionBlock ~braces:true e cmtTbl
    | Pexp_assert expr ->
      let rhs =
        let doc = printExpressionWithComments expr cmtTbl in
        match Parens.lazyOrAssertExprRhs expr with
        | Parens.Parenthesized -> addParens doc
        | Braced braces  -> printBraces doc expr braces
        | Nothing -> doc
      in
      Doc.concat [
        Doc.text "assert ";
        rhs;
      ]
    | Pexp_lazy expr ->
      let rhs =
        let doc = printExpressionWithComments expr cmtTbl in
        match Parens.lazyOrAssertExprRhs expr with
        | Parens.Parenthesized -> addParens doc
        | Braced braces  -> printBraces doc expr braces
        | Nothing -> doc
      in
      Doc.group (
        Doc.concat [
          Doc.text "lazy ";
          rhs;
        ]
      )
    | Pexp_open (overrideFlag, longidentLoc, expr) ->
      printExpressionBlock ~braces:true e cmtTbl
    | Pexp_pack (modExpr) ->
      Doc.group (Doc.concat [
        Doc.text "module(";
        Doc.indent (
          Doc.concat [
            Doc.softLine;
            printModExpr modExpr cmtTbl;
          ]
        );
        Doc.softLine;
        Doc.rparen;
      ])
    | Pexp_sequence _ ->
      printExpressionBlock ~braces:true e cmtTbl
    | Pexp_let _ ->
      printExpressionBlock ~braces:true e cmtTbl
    | Pexp_fun _ | Pexp_newtype _ ->
      let (attrsOnArrow, parameters, returnExpr) = ParsetreeViewer.funExpr e in
      let (uncurried, attrs) =
        ParsetreeViewer.processUncurriedAttribute attrsOnArrow
      in
      let (returnExpr, typConstraint) = match returnExpr.pexp_desc with
      | Pexp_constraint (expr, typ) -> (
          {expr with pexp_attributes = List.concat [
            expr.pexp_attributes;
            returnExpr.pexp_attributes;
          ]},
          Some typ
        )
      | _ -> (returnExpr, None)
      in
      let hasConstraint = match typConstraint with | Some _ -> true | None -> false in
      let parametersDoc = printExprFunParameters
        ~inCallback:false
        ~uncurried
        ~hasConstraint
        parameters
        cmtTbl
      in
      let returnExprDoc =
        let (optBraces, _) = ParsetreeViewer.processBracesAttr returnExpr in
        let shouldInline = match (returnExpr.pexp_desc, optBraces) with
        | (_, Some _ ) -> true
        | ((Pexp_array _
        | Pexp_tuple _
        | Pexp_construct (_, Some _)
        | Pexp_record _), _) -> true
        | _ -> false
        in
        let shouldIndent = match returnExpr.pexp_desc with
        | Pexp_sequence _
        | Pexp_let _
        | Pexp_letmodule _
        | Pexp_letexception _
        | Pexp_open _ -> false
        | _ -> true
        in
        let returnDoc =
          let doc = printExpressionWithComments returnExpr cmtTbl in
          match Parens.expr returnExpr with
          | Parens.Parenthesized -> addParens doc
          | Braced braces  -> printBraces doc returnExpr braces
          | Nothing -> doc
        in
        if shouldInline then Doc.concat [
          Doc.space;
          returnDoc;
        ] else
          Doc.group (
            if shouldIndent then
              Doc.indent (
                Doc.concat [
                  Doc.line;
                  returnDoc;
                ]
              )
            else
              Doc.concat [
                Doc.space;
                returnDoc
              ]
          )
      in
      let typConstraintDoc = match typConstraint with
      | Some(typ) -> Doc.concat [Doc.text ": "; printTypExpr typ cmtTbl]
      | _ -> Doc.nil
      in
      let attrs = printAttributes attrs in
      Doc.group (
        Doc.concat [
          attrs;
          parametersDoc;
          typConstraintDoc;
          Doc.text " =>";
          returnExprDoc;
        ]
      )
    | Pexp_try (expr, cases) ->
      let exprDoc =
        let doc = printExpressionWithComments expr cmtTbl in
        match Parens.expr expr with
        | Parens.Parenthesized -> addParens doc
        | Braced braces  -> printBraces doc expr braces
        | Nothing -> doc
      in
      Doc.concat [
        Doc.text "try ";
        exprDoc;
        Doc.text " catch ";
        printCases cases cmtTbl;
      ]
    | Pexp_match (expr, cases) ->
      let exprDoc =
        let doc = printExpressionWithComments expr cmtTbl in
        match Parens.expr expr with
        | Parens.Parenthesized -> addParens doc
        | Braced braces  -> printBraces doc expr braces
        | Nothing -> doc
      in
      Doc.concat [
        Doc.text "switch ";
        exprDoc;
        Doc.space;
        printCases cases cmtTbl;
      ]
    | Pexp_function cases ->
      Doc.concat [
        Doc.text "x => switch x ";
        printCases cases cmtTbl;
      ]
    | _ -> failwith "expression not yet implemented in printer"
    in
    let shouldPrintItsOwnAttributes = match e.pexp_desc with
    | Pexp_apply _
    | Pexp_fun _
    | Pexp_newtype _
    | Pexp_setfield _
    | Pexp_ifthenelse _ -> true
    | Pexp_construct _ when ParsetreeViewer.hasJsxAttribute e.pexp_attributes -> true
    | _ -> false
    in
    match e.pexp_attributes with
    | [] -> printedExpression
    | attrs when not shouldPrintItsOwnAttributes ->
      Doc.group (
        Doc.concat [
          printAttributes attrs;
          printedExpression;
        ]
      )
    | _ -> printedExpression

  and printPexpFun ~inCallback e cmtTbl =
      let (attrsOnArrow, parameters, returnExpr) = ParsetreeViewer.funExpr e in
      let (uncurried, attrs) =
        ParsetreeViewer.processUncurriedAttribute attrsOnArrow
      in
      let (returnExpr, typConstraint) = match returnExpr.pexp_desc with
      | Pexp_constraint (expr, typ) -> (
          {expr with pexp_attributes = List.concat [
            expr.pexp_attributes;
            returnExpr.pexp_attributes;
          ]},
          Some typ
        )
      | _ -> (returnExpr, None)
      in
      let parametersDoc = printExprFunParameters
        ~inCallback
        ~uncurried
        ~hasConstraint:(match typConstraint with | Some _ -> true | None -> false)
        parameters cmtTbl in
      let returnShouldIndent = match returnExpr.pexp_desc with
      | Pexp_sequence _ | Pexp_let _ | Pexp_letmodule _ | Pexp_letexception _ | Pexp_open _ -> false
      | _ -> true
      in
      let returnExprDoc =
        let (optBraces, _) = ParsetreeViewer.processBracesAttr returnExpr in
        let shouldInline = match (returnExpr.pexp_desc, optBraces) with
        | (_, Some _) -> true
        | ((Pexp_array _
        | Pexp_tuple _
        | Pexp_construct (_, Some _)
        | Pexp_record _), _) -> true
        | _ -> false
        in
        let returnDoc =
          let doc = printExpressionWithComments returnExpr cmtTbl in
          match Parens.expr returnExpr with
          | Parens.Parenthesized -> addParens doc
          | Braced braces  -> printBraces doc returnExpr braces
          | Nothing -> doc
        in
        if shouldInline then Doc.concat [
          Doc.space;
          returnDoc;
        ] else
          Doc.group (
            if returnShouldIndent then
              Doc.concat [
                Doc.indent (
                  Doc.concat [
                    Doc.line;
                    returnDoc;
                  ]
                );
                if inCallback then Doc.softLine else Doc.nil;
              ]
            else
              Doc.concat [
                Doc.space;
                returnDoc;
              ]
          )
      in
      let typConstraintDoc = match typConstraint with
      | Some(typ) -> Doc.concat [
          Doc.text ": ";
          printTypExpr typ cmtTbl
        ]
      | _ -> Doc.nil
      in
      let attrs = match attrs with
      | [] -> Doc.nil
      | attrs -> Doc.concat [
          Doc.join ~sep:Doc.line (List.map printAttribute attrs);
          Doc.space;
        ]
      in
      Doc.group (
        Doc.concat [
          attrs;
          parametersDoc;
          typConstraintDoc;
          Doc.text " =>";
          returnExprDoc;
        ]
      )

  and printTernaryOperand expr cmtTbl =
    let doc = printExpressionWithComments expr cmtTbl in
    match Parens.ternaryOperand expr with
    | Parens.Parenthesized -> addParens doc
    | Braced braces  -> printBraces doc expr braces
    | Nothing -> doc

  and printSetFieldExpr attrs lhs longidentLoc rhs loc cmtTbl =
    let rhsDoc =
      let doc = printExpressionWithComments rhs cmtTbl in
      match Parens.setFieldExprRhs rhs with
      | Parens.Parenthesized -> addParens doc
      | Braced braces  -> printBraces doc rhs braces
      | Nothing -> doc
    in
    let lhsDoc =
      let doc = printExpressionWithComments lhs cmtTbl in
      match Parens.fieldExpr lhs with
      | Parens.Parenthesized -> addParens doc
      | Braced braces  -> printBraces doc lhs braces
      | Nothing -> doc
    in
    let shouldIndent = ParsetreeViewer.isBinaryExpression rhs in
    let doc = Doc.group (Doc.concat [
      lhsDoc;
      Doc.dot;
      printLongidentLocation longidentLoc cmtTbl;
      Doc.text " =";
      if shouldIndent then Doc.group (
        Doc.indent (
          (Doc.concat [Doc.line; rhsDoc])
        )
      ) else
        Doc.concat [Doc.space; rhsDoc]
    ]) in
    let doc = match attrs with
    | [] -> doc
    | attrs ->
      Doc.group (
        Doc.concat [
          printAttributes attrs;
          doc
        ]
      )
    in
    printComments doc cmtTbl loc

  and printTemplateLiteral expr cmtTbl =
    let rec walkExpr expr =
      let open Parsetree in
      match expr.pexp_desc with
      | Pexp_apply (
          {pexp_desc = Pexp_ident {txt = Longident.Lident "^"}},
          [Nolabel, arg1; Nolabel, arg2]
        ) ->
          let lhs = walkExpr arg1 in
          let rhs = walkExpr arg2 in
          Doc.concat [lhs; rhs]
      | Pexp_constant (Pconst_string (txt, Some "j")) -> Doc.text txt
      | _ ->
        let doc = printExpressionWithComments expr cmtTbl in
        Doc.concat [Doc.text "${"; doc; Doc.rbrace]
    in
    let content = walkExpr expr in
    Doc.concat [Doc.text "`"; content; Doc.text "`"]

  and printUnaryExpression expr cmtTbl =
    let printUnaryOperator op = Doc.text (
      match op with
      | "~+" -> "+"
      | "~+." -> "+."
      | "~-" -> "-"
      | "~-." ->  "-."
      | "not" -> "!"
      | "!" -> "&"
      | _ -> assert false
    ) in
    match expr.pexp_desc with
    | Pexp_apply (
        {pexp_desc = Pexp_ident {txt = Longident.Lident operator}},
        [Nolabel, operand]
      ) ->
      let printedOperand =
        let doc = printExpressionWithComments operand cmtTbl in
        match Parens.unaryExprOperand operand with
        | Parens.Parenthesized -> addParens doc
        | Braced braces  -> printBraces doc operand braces
        | Nothing -> doc
      in
      let doc = Doc.concat [
        printUnaryOperator operator;
        printedOperand;
      ] in
      printComments doc cmtTbl expr.pexp_loc
    | _ -> assert false

  and printBinaryExpression (expr : Parsetree.expression) cmtTbl =
    let printBinaryOperator ~inlineRhs operator =
      let operatorTxt = match operator with
      | "|." -> "->"
      | "^" -> "++"
      | "=" -> "=="
      | "==" -> "==="
      | "<>" -> "!="
      | "!=" -> "!=="
      | txt -> txt
      in
      let spacingBeforeOperator =
        if operator = "|." then Doc.softLine
        else if operator = "|>" then Doc.line
        else Doc.space;
      in
      let spacingAfterOperator =
        if operator = "|." then Doc.nil
        else if operator = "|>" then Doc.space
        else if inlineRhs then Doc.space else Doc.line
      in
      Doc.concat [
        spacingBeforeOperator;
        Doc.text operatorTxt;
        spacingAfterOperator;
      ]
    in
    let printOperand ~isLhs expr parentOperator =
      let rec flatten ~isLhs expr parentOperator =
        if ParsetreeViewer.isBinaryExpression expr then
          begin match expr with
          | {pexp_desc = Pexp_apply (
              {pexp_desc = Pexp_ident {txt = Longident.Lident operator}},
              [_, left; _, right]
            )} ->
            if ParsetreeViewer.flattenableOperators parentOperator operator &&
               not (ParsetreeViewer.hasAttributes expr.pexp_attributes)
            then
              let leftPrinted = flatten ~isLhs:true left operator in
              let rightPrinted =
                let (_, rightAttrs) =
                  ParsetreeViewer.partitionPrinteableAttributes right.pexp_attributes
                in
                let doc =
                  printExpressionWithComments
                    {right with pexp_attributes = rightAttrs}
                    cmtTbl
                in
                let doc = if Parens.flattenOperandRhs parentOperator right then
                  Doc.concat [Doc.lparen; doc; Doc.rparen]
                else
                  doc
                in
                let printeableAttrs =
                  ParsetreeViewer.filterPrinteableAttributes right.pexp_attributes
                in
                Doc.concat [printAttributes printeableAttrs; doc]
              in
              let doc = Doc.concat [
                leftPrinted;
                printBinaryOperator ~inlineRhs:false operator;
                rightPrinted;
              ] in
              let doc =
                if not isLhs && (Parens.rhsBinaryExprOperand operator expr) then
                  Doc.concat [Doc.lparen; doc; Doc.rparen]
                else doc
              in
              printComments doc cmtTbl expr.pexp_loc
            else (
              let doc = printExpressionWithComments {expr with pexp_attributes = []} cmtTbl in
              let doc = if Parens.subBinaryExprOperand parentOperator operator ||
                (expr.pexp_attributes <> [] &&
                  (ParsetreeViewer.isBinaryExpression expr ||
                ParsetreeViewer.isTernaryExpr expr))
              then
                Doc.concat [Doc.lparen; doc; Doc.rparen]
              else doc
              in Doc.concat [
                printAttributes expr.pexp_attributes;
                doc
              ]
            )
          | _ -> assert false
          end
        else
          begin match expr.pexp_desc with
          | Pexp_setfield (lhs, field, rhs) ->
            let doc = printSetFieldExpr expr.pexp_attributes lhs field rhs expr.pexp_loc cmtTbl  in
            if isLhs then addParens doc else doc
          | Pexp_apply(
              {pexp_desc = Pexp_ident {txt = Longident.Lident "#="}},
              [(Nolabel, lhs); (Nolabel, rhs)]
            ) ->
            let rhsDoc = printExpressionWithComments rhs cmtTbl in
            let lhsDoc = printExpressionWithComments lhs cmtTbl in
            (* TODO: unify indentation of "=" *)
            let shouldIndent = ParsetreeViewer.isBinaryExpression rhs in
            let doc = Doc.group (
              Doc.concat [
                lhsDoc;
                Doc.text " =";
                if shouldIndent then Doc.group (
                  Doc.indent (Doc.concat [Doc.line; rhsDoc])
                ) else
                  Doc.concat [Doc.space; rhsDoc]
              ]
            ) in
            let doc = match expr.pexp_attributes with
            | [] -> doc
            | attrs ->
              Doc.group (
                Doc.concat [
                  printAttributes attrs;
                  doc
                ]
              )
            in
            if isLhs then addParens doc else doc
          | _ ->
            let doc = printExpressionWithComments expr cmtTbl in
            begin match Parens.binaryExprOperand ~isLhs expr parentOperator with
            | Parens.Parenthesized -> addParens doc
            | Braced braces  -> printBraces doc expr braces
            | Nothing -> doc
            end
          end
      in
      flatten ~isLhs expr parentOperator
    in
    match expr.pexp_desc with
    | Pexp_apply (
        {pexp_desc = Pexp_ident {txt = Longident.Lident (("|." | "|>") as op)}},
        [Nolabel, lhs; Nolabel, rhs]
      ) when not (
          ParsetreeViewer.isBinaryExpression lhs ||
          ParsetreeViewer.isBinaryExpression rhs
      ) ->
      let lhsDoc = printOperand ~isLhs:true lhs op in
      let rhsDoc = printOperand ~isLhs:false rhs op in
      Doc.group (
        Doc.concat [
          lhsDoc;
          (match op with
          | "|." -> Doc.text "->"
          | "|>" -> Doc.text " |> "
          | _ -> assert false);
          rhsDoc;
        ]
      )
    | Pexp_apply (
        {pexp_desc = Pexp_ident {txt = Longident.Lident operator}},
        [Nolabel, lhs; Nolabel, rhs]
      ) ->
      let right =
        let operatorWithRhs =
          let rhsDoc = printOperand ~isLhs:false rhs operator in
          Doc.concat [
            printBinaryOperator
              ~inlineRhs:(ParsetreeViewer.shouldInlineRhsBinaryExpr rhs) operator;
            rhsDoc;
        ] in
        if ParsetreeViewer.shouldIndentBinaryExpr expr then
          Doc.group (Doc.indent operatorWithRhs)
        else operatorWithRhs
      in
      let doc = Doc.group (
        Doc.concat [
          printOperand ~isLhs:true lhs operator;
          right
        ]
      ) in
      Doc.group (
        Doc.concat [
          printAttributes expr.pexp_attributes;
          match Parens.binaryExpr {expr with
            pexp_attributes = List.filter (fun attr ->
              match attr with
              | ({Location.txt = ("ns.braces")}, _) -> false
              | _ -> true
            ) expr.pexp_attributes
          } with
          | Braced(bracesLoc) -> printBraces doc expr bracesLoc
          | Parenthesized -> addParens doc
          | Nothing -> doc;
        ]
      )
    | _ -> Doc.nil

  (* callExpr(arg1, arg2) *)
  and printPexpApply expr cmtTbl =
    match expr.pexp_desc with
    | Pexp_apply (
        {pexp_desc = Pexp_ident {txt = Longident.Lident "##"}},
        [Nolabel, parentExpr; Nolabel, memberExpr]
      ) ->
        let parentDoc =
          let doc = printExpressionWithComments parentExpr cmtTbl in
          match Parens.expr parentExpr with
          | Parens.Parenthesized -> addParens doc
          | Braced braces  -> printBraces doc parentExpr braces
          | Nothing -> doc
        in
        let member =
          let memberDoc = printExpressionWithComments memberExpr cmtTbl in
          Doc.concat [Doc.text "\""; memberDoc; Doc.text "\""]
        in
        Doc.group (Doc.concat [
          printAttributes expr.pexp_attributes;
          parentDoc;
          Doc.lbracket;
          member;
          Doc.rbracket;
        ])
    | Pexp_apply (
        {pexp_desc = Pexp_ident {txt = Longident.Lident "#="}},
        [Nolabel, lhs; Nolabel, rhs]
      ) ->
        let rhsDoc =
          let doc = printExpressionWithComments rhs cmtTbl in
          match Parens.expr rhs with
          | Parens.Parenthesized -> addParens doc
          | Braced braces  -> printBraces doc rhs braces
          | Nothing -> doc
        in
        (* TODO: unify indentation of "=" *)
        let shouldIndent = not (ParsetreeViewer.isBracedExpr rhs) && ParsetreeViewer.isBinaryExpression rhs in
        let doc = Doc.group(
          Doc.concat [
            printExpressionWithComments lhs cmtTbl;
            Doc.text " =";
            if shouldIndent then Doc.group (
              Doc.indent (
                (Doc.concat [Doc.line; rhsDoc])
              )
            ) else
              Doc.concat [Doc.space; rhsDoc]
          ]
        ) in
        begin match expr.pexp_attributes with
        | [] -> doc
        | attrs ->
          Doc.group (
            Doc.concat [
              printAttributes attrs;
              doc
            ]
          )
        end
    | Pexp_apply (
        {pexp_desc = Pexp_ident {txt = Longident.Ldot (Lident "Array", "get")}},
        [Nolabel, parentExpr; Nolabel, memberExpr]
      ) ->
        let member =
          let memberDoc =
            let doc = printExpressionWithComments memberExpr cmtTbl in
            match Parens.expr memberExpr with
            | Parens.Parenthesized -> addParens doc
            | Braced braces  -> printBraces doc memberExpr braces
            | Nothing -> doc
          in
          let shouldInline = match memberExpr.pexp_desc with
          | Pexp_constant _ | Pexp_ident _ -> true
          | _ -> false
          in
          if shouldInline then memberDoc else (
            Doc.concat [
              Doc.indent (
                Doc.concat [
                  Doc.softLine;
                  memberDoc;
                ]
              );
              Doc.softLine
            ]
          )
        in
        let parentDoc =
          let doc = printExpressionWithComments parentExpr cmtTbl in
          match Parens.expr parentExpr with
          | Parens.Parenthesized -> addParens doc
          | Braced braces  -> printBraces doc parentExpr braces
          | Nothing -> doc
        in
        Doc.group (Doc.concat [
          printAttributes expr.pexp_attributes;
          parentDoc;
          Doc.lbracket;
          member;
          Doc.rbracket;
        ])
    | Pexp_apply (
        {pexp_desc = Pexp_ident {txt = Longident.Ldot (Lident "Array", "set")}},
        [Nolabel, parentExpr; Nolabel, memberExpr; Nolabel, targetExpr]
      ) ->
        let member =
          let memberDoc =
            let doc = printExpressionWithComments memberExpr cmtTbl in
            match Parens.expr memberExpr with
            | Parens.Parenthesized -> addParens doc
            | Braced braces  -> printBraces doc memberExpr braces
            | Nothing -> doc
          in
          let shouldInline = match memberExpr.pexp_desc with
          | Pexp_constant _ | Pexp_ident _ -> true
          | _ -> false
          in
          if shouldInline then memberDoc else (
            Doc.concat [
              Doc.indent (
                Doc.concat [
                  Doc.softLine;
                  memberDoc;
                ]
              );
              Doc.softLine
            ]
          )
        in
        let shouldIndentTargetExpr =
          if ParsetreeViewer.isBracedExpr targetExpr then
            false
          else
          ParsetreeViewer.isBinaryExpression targetExpr ||
          (match targetExpr with
          | {
              pexp_attributes = [({Location.txt="ns.ternary"}, _)];
              pexp_desc = Pexp_ifthenelse (ifExpr, _, _)
            }  ->
            ParsetreeViewer.isBinaryExpression ifExpr || ParsetreeViewer.hasAttributes ifExpr.pexp_attributes
        | { pexp_desc = Pexp_newtype _} -> false
        | e ->
            ParsetreeViewer.hasAttributes e.pexp_attributes ||
            ParsetreeViewer.isArrayAccess e
          )
        in
        let targetExpr =
          let doc = printExpressionWithComments targetExpr cmtTbl in
          match Parens.expr targetExpr with
          | Parens.Parenthesized -> addParens doc
          | Braced braces  -> printBraces doc targetExpr braces
          | Nothing -> doc
        in
        let parentDoc =
          let doc = printExpressionWithComments parentExpr cmtTbl in
          match Parens.expr parentExpr with
          | Parens.Parenthesized -> addParens doc
          | Braced braces  -> printBraces doc parentExpr braces
          | Nothing -> doc
        in
        Doc.group (
          Doc.concat [
          printAttributes expr.pexp_attributes;
          parentDoc;
          Doc.lbracket;
          member;
          Doc.rbracket;
          Doc.text " =";
          if shouldIndentTargetExpr then
            Doc.indent (
              Doc.concat [
                Doc.line;
                targetExpr;
              ]
            )
          else
            Doc.concat [
              Doc.space;
              targetExpr;
            ]
          ]
        )
    (* TODO: cleanup, are those branches even remotely performant? *)
    | Pexp_apply (
        {pexp_desc = Pexp_ident lident},
        args
      ) when ParsetreeViewer.isJsxExpression expr ->
      printJsxExpression lident args cmtTbl
    | Pexp_apply (callExpr, args) ->
      let (uncurried, attrs) =
        ParsetreeViewer.processUncurriedAttribute expr.pexp_attributes
      in
      let callExprDoc =
        let doc = printExpressionWithComments callExpr cmtTbl in
        match Parens.callExpr callExpr with
        | Parens.Parenthesized -> addParens doc
        | Braced braces  -> printBraces doc callExpr braces
        | Nothing -> doc
      in
      if ParsetreeViewer.requiresSpecialCallbackPrintingFirstArg args then
        let argsDoc =
          printArgumentsWithCallbackInFirstPosition ~uncurried args cmtTbl
        in
        Doc.concat [
          printAttributes attrs;
          callExprDoc;
          argsDoc;
        ]
      else if ParsetreeViewer.requiresSpecialCallbackPrintingLastArg args then
        let argsDoc =
          printArgumentsWithCallbackInLastPosition ~uncurried args cmtTbl
        in
        Doc.concat [
          printAttributes attrs;
          callExprDoc;
          argsDoc;
        ]
      else
        let argsDoc = printArguments ~uncurried args cmtTbl in
        Doc.concat [
          printAttributes attrs;
          callExprDoc;
          argsDoc;
        ]
    | _ -> assert false

  and printJsxExpression lident args cmtTbl =
    let name = printJsxName lident cmtTbl in
    let (formattedProps, children) = printJsxProps args cmtTbl in
    (* <div className="test" /> *)
    let isSelfClosing = match children with | [] -> true | _ -> false in
    Doc.group (
      Doc.concat [
        Doc.group (
          Doc.concat [
            Doc.lessThan;
            name;
            formattedProps;
            if isSelfClosing then Doc.concat [Doc.line; Doc.text "/>"] else Doc.nil
          ]
        );
        if isSelfClosing then Doc.nil
        else
          Doc.concat [
            Doc.greaterThan;
            Doc.indent (
              Doc.concat [
                Doc.line;
                printJsxChildren children cmtTbl;
              ]
            );
            Doc.line;
            Doc.text "</";
            name;
            Doc.greaterThan;
          ]
      ]
    )

  and printJsxFragment expr cmtTbl =
    let opening = Doc.text "<>" in
    let closing = Doc.text "</>" in
    let (children, _) = ParsetreeViewer.collectListExpressions expr in
    Doc.group (
      Doc.concat [
        opening;
        begin match children with
        | [] -> Doc.nil
        | children ->
          Doc.indent (
            Doc.concat [
              Doc.line;
              printJsxChildren children cmtTbl;
            ]
          )
        end;
        Doc.line;
        closing;
      ]
    )

  and printJsxChildren (children: Parsetree.expression list) cmtTbl =
    Doc.group (
      Doc.join ~sep:Doc.line (
        List.map (fun expr ->
          let exprDoc = printExpressionWithComments expr cmtTbl in
          match Parens.jsxChildExpr expr with
          | Parenthesized
          | Braced _ -> addBraces exprDoc
          | Nothing -> exprDoc
        ) children
      )
    )

  and printJsxProps args cmtTbl =
    let rec loop props args =
      match args with
      | [] -> (Doc.nil, [])
      | [
          (Asttypes.Labelled "children", children);
          (
            Asttypes.Nolabel,
            {Parsetree.pexp_desc = Pexp_construct ({txt = Longident.Lident "()"}, None)}
          )
        ] ->
        let formattedProps = Doc.indent (
          match props with
          | [] -> Doc.nil
          | props ->
            Doc.concat [
              Doc.line;
              Doc.group (
                Doc.join ~sep:Doc.line (props |> List.rev)
              )
            ]
        ) in
        let (children, _) = ParsetreeViewer.collectListExpressions children in
        (formattedProps, children)
      | arg::args ->
        let propDoc = printJsxProp arg cmtTbl in
        loop (propDoc::props) args
    in
    loop [] args

  and printJsxProp arg cmtTbl =
    match arg with
    | (
        (Asttypes.Labelled lblTxt | Optional lblTxt) as lbl,
        {
          Parsetree.pexp_attributes = [({Location.txt = "ns.jsxPropLoc"; loc = argLoc}, _)];
          pexp_desc = Pexp_ident {txt = Longident.Lident ident}
        }
      ) when lblTxt = ident (* jsx punning *) ->
      begin match lbl with
      | Nolabel -> Doc.nil
      | Labelled lbl ->
        printComments (printIdentLike ident) cmtTbl argLoc
      | Optional lbl ->
        let doc = Doc.concat [
          Doc.question;
          printIdentLike ident;
        ] in
        printComments doc cmtTbl argLoc
      end
    | (lbl, expr) ->
      let (argLoc, expr) = match expr.pexp_attributes with
      | ({Location.txt = "ns.jsxPropLoc"; loc}, _)::attrs ->
          (loc, {expr with pexp_attributes = attrs})
      | _ ->
        Location.none, expr
      in
      let lblDoc = match lbl with
      | Asttypes.Labelled lbl ->
        let lbl = printComments (printIdentLike lbl) cmtTbl argLoc in
        Doc.concat [lbl; Doc.equal]
      | Asttypes.Optional lbl ->
        let lbl = printComments (printIdentLike lbl) cmtTbl argLoc in
        Doc.concat [lbl; Doc.equal; Doc.question]
      | Nolabel -> Doc.nil
      in
      let exprDoc =
        let doc = printExpression expr cmtTbl in
        match Parens.jsxPropExpr expr with
        | Parenthesized | Braced(_) -> addBraces doc
        | _ -> doc
      in
      let fullLoc = {argLoc with loc_end = expr.pexp_loc.loc_end} in
      printComments
        (Doc.concat [
          lblDoc;
          exprDoc;
        ])
        cmtTbl
        fullLoc

  (* div -> div.
   * Navabar.createElement -> Navbar
   * Staff.Users.createElement -> Staff.Users *)
  and printJsxName {txt = lident; loc} cmtTbl =
    let rec flatten acc lident = match lident with
    | Longident.Lident txt -> txt::acc
    | Ldot (lident, txt) ->
      let acc = if txt = "createElement" then acc else txt::acc in
      flatten acc lident
    | _ -> acc
    in
    let doc = match lident with
    | Longident.Lident txt -> Doc.text txt
    | _ as lident ->
      let segments = flatten [] lident in
      Doc.join ~sep:Doc.dot (List.map Doc.text segments)
    in
    printComments doc cmtTbl loc

  and printArgumentsWithCallbackInFirstPosition ~uncurried args cmtTbl =
    let (callback, printedArgs) = match args with
    | (lbl, expr)::args ->
      let lblDoc = match lbl with
      | Asttypes.Nolabel -> Doc.nil
      | Asttypes.Labelled txt ->
        Doc.concat [
          Doc.tilde; printIdentLike txt; Doc.equal;
        ]
      | Asttypes.Optional txt ->
        Doc.concat [
          Doc.tilde; printIdentLike txt; Doc.equal; Doc.question;
        ]
      in
      let callback = Doc.concat [
        lblDoc;
        printPexpFun ~inCallback:true expr cmtTbl
      ] in
      let printedArgs = List.map (fun arg ->
        printArgument arg cmtTbl
      ) args |> Doc.join ~sep:(Doc.concat [Doc.comma; Doc.line])
      in
      (callback, printedArgs)
    | _ -> assert false
    in
    (* Thing.map((arg1, arg2) => MyModuleBlah.toList(argument), foo) *)
    (* Thing.map((arg1, arg2) => {
     *   MyModuleBlah.toList(argument)
     * }, longArgumet, veryLooooongArgument)
     *)
    let fitsOnOneLine = Doc.concat [
      if uncurried then Doc.text "(. " else Doc.lparen;
      callback;
      Doc.comma;
      Doc.line;
      printedArgs;
      Doc.rparen;
    ] in

    (* Thing.map(
     *   (param1, parm2) => doStuff(param1, parm2),
     *   arg1,
     *   arg2,
     *   arg3,
     * )
     *)
    let breakAllArgs = printArguments ~uncurried args cmtTbl in
    Doc.customLayout [
      fitsOnOneLine;
      breakAllArgs;
    ]

  and printArgumentsWithCallbackInLastPosition ~uncurried args cmtTbl =
    let rec loop acc args = match args with
    | [] -> (Doc.nil, Doc.nil)
    | [lbl, expr] ->
      let lblDoc = match lbl with
      | Asttypes.Nolabel -> Doc.nil
      | Asttypes.Labelled txt ->
        Doc.concat [
          Doc.tilde; printIdentLike txt; Doc.equal;
        ]
      | Asttypes.Optional txt ->
        Doc.concat [
          Doc.tilde; printIdentLike txt; Doc.equal; Doc.question;
        ]
      in
      let callback = printPexpFun ~inCallback:true expr cmtTbl in
      (Doc.concat (List.rev acc), Doc.concat [lblDoc; callback])
    | arg::args ->
      let argDoc = printArgument arg cmtTbl in
      loop (Doc.line::Doc.comma::argDoc::acc) args
    in
    let (printedArgs, callback) = loop [] args in

    (* Thing.map(foo, (arg1, arg2) => MyModuleBlah.toList(argument)) *)
    let fitsOnOneLine = Doc.concat [
      if uncurried then Doc.text "(." else Doc.lparen;
      printedArgs;
      callback;
      Doc.rparen;
    ] in

    (* Thing.map(longArgumet, veryLooooongArgument, (arg1, arg2) =>
     *   MyModuleBlah.toList(argument)
     * )
     *)
    let arugmentsFitOnOneLine =
      Doc.concat [
        if uncurried then Doc.text "(." else Doc.lparen;
        Doc.softLine;
        printedArgs;
        Doc.breakableGroup ~forceBreak:true callback;
        Doc.softLine;
        Doc.rparen;
      ]
    in

    (* Thing.map(
     *   arg1,
     *   arg2,
     *   arg3,
     *   (param1, parm2) => doStuff(param1, parm2)
     * )
     *)
    let breakAllArgs = printArguments ~uncurried args cmtTbl in
    Doc.customLayout [
      fitsOnOneLine;
      arugmentsFitOnOneLine;
      breakAllArgs;
    ]

	and printArguments ~uncurried (args : (Asttypes.arg_label * Parsetree.expression) list) cmtTbl =
		match args with
		| [Nolabel, {pexp_desc = Pexp_construct ({txt = Longident.Lident "()"}, _)}] ->
      if uncurried then Doc.text "(.)" else Doc.text "()"
    | [(Nolabel, arg)] when ParsetreeViewer.isHuggableExpression arg ->
      let argDoc =
        let doc = printExpressionWithComments arg cmtTbl in
        match Parens.expr arg with
        | Parens.Parenthesized -> addParens doc
        | Braced braces  -> printBraces doc arg braces
        | Nothing -> doc
      in
      Doc.concat [
        if uncurried then Doc.text "(." else Doc.lparen;
        argDoc;
        Doc.rparen;
      ]
		| args -> Doc.group (
				Doc.concat [
          if uncurried then Doc.text "(." else Doc.lparen;
					Doc.indent (
						Doc.concat [
              if uncurried then Doc.line else Doc.softLine;
							Doc.join ~sep:(Doc.concat [Doc.comma; Doc.line]) (
								List.map (fun arg -> printArgument arg cmtTbl) args
							)
						]
					);
					Doc.trailingComma;
					Doc.softLine;
					Doc.rparen;
				]
			)

(*
   * argument ::=
   *   | _                            (* syntax sugar *)
   *   | expr
   *   | expr : type
   *   | ~ label-name
   *   | ~ label-name
   *   | ~ label-name ?
   *   | ~ label-name =   expr
   *   | ~ label-name =   _           (* syntax sugar *)
   *   | ~ label-name =   expr : type
   *   | ~ label-name = ? expr
   *   | ~ label-name = ? _           (* syntax sugar *)
   *   | ~ label-name = ? expr : type *)
	and printArgument (argLbl, arg) cmtTbl =
		match (argLbl, arg) with
		(* ~a (punned)*)
		| (
				(Asttypes.Labelled lbl),
				({pexp_desc=Pexp_ident {txt = Longident.Lident name}} as argExpr)
			) when lbl = name && not (ParsetreeViewer.isBracedExpr argExpr) ->
			Doc.concat [
        Doc.tilde;
        printIdentLike lbl
      ]
		(* ~a? (optional lbl punned)*)
		| (
				(Asttypes.Optional lbl),
				{pexp_desc=Pexp_ident {txt = Longident.Lident name}}
			) when lbl = name ->
      Doc.concat [
        Doc.tilde;
        printIdentLike lbl;
        Doc.question;
      ]
		| (lbl, expr) ->
			let printedLbl = match argLbl with
			| Asttypes.Nolabel -> Doc.nil
			| Asttypes.Labelled lbl ->
        Doc.concat [Doc.tilde; printIdentLike lbl; Doc.equal]
			| Asttypes.Optional lbl ->
        Doc.concat [Doc.tilde; printIdentLike lbl; Doc.equal; Doc.question]
			in
			let printedExpr =
        let doc = printExpressionWithComments expr cmtTbl in
        match Parens.expr expr with
        | Parens.Parenthesized -> addParens doc
        | Braced braces  -> printBraces doc expr braces
        | Nothing -> doc
      in
			Doc.concat [
				printedLbl;
				printedExpr;
			]

  and printCases (cases: Parsetree.case list) cmtTbl =
    Doc.breakableGroup ~forceBreak:true (
      Doc.concat [
        Doc.lbrace;
          Doc.concat [
            Doc.line;
            printList
              ~getLoc:(fun n -> {n.Parsetree.pc_lhs.ppat_loc with
                loc_end = n.pc_rhs.pexp_loc.loc_end
              })
              ~print:printCase
              ~nodes:cases
              cmtTbl
          ];
        Doc.line;
        Doc.rbrace;
      ]
    )

  and printCase (case: Parsetree.case) cmtTbl =
    let rhs = match case.pc_rhs.pexp_desc with
    | Pexp_let _
    | Pexp_letmodule _
    | Pexp_letexception _
    | Pexp_open _
    | Pexp_sequence _ ->
      printExpressionBlock ~braces:false case.pc_rhs cmtTbl
    | _ -> printExpressionWithComments case.pc_rhs cmtTbl
    in
    let guard = match case.pc_guard with
    | None -> Doc.nil
    | Some expr -> Doc.group (
        Doc.concat [
          Doc.line;
          Doc.text "when ";
          printExpressionWithComments expr cmtTbl;
        ]
      )
    in
    let shouldInlineRhs = match case.pc_rhs.pexp_desc with
    | Pexp_construct ({txt = Longident.Lident ("()" | "true" | "false")}, _)
    | Pexp_constant _
    | Pexp_ident _ -> true
    | _ when ParsetreeViewer.isHuggableRhs case.pc_rhs -> true
    | _ -> false
    in
    let shouldIndentPattern = match case.pc_lhs.ppat_desc with
    | Ppat_or _ -> false
    | _ -> true
    in
    let patternDoc = printPattern case.pc_lhs cmtTbl in
    let content = Doc.concat [
      if shouldIndentPattern then Doc.indent patternDoc else patternDoc;
      Doc.indent guard;
      Doc.text " =>";
      Doc.indent (
        Doc.concat [
          if shouldInlineRhs then Doc.space else Doc.line;
          rhs;
        ]
      )
    ] in
    Doc.group (
      Doc.concat [
        Doc.text "| ";
        content;
      ]
    )

  and printExprFunParameters ~inCallback ~uncurried ~hasConstraint parameters cmtTbl =
    match parameters with
    (* let f = _ => () *)
    | [([], Asttypes.Nolabel, None, {Parsetree.ppat_desc = Ppat_any})] when not uncurried ->
      if hasConstraint then Doc.text "(_)" else Doc.text "_"
    (* let f = a => () *)
    | [([], Asttypes.Nolabel, None, {Parsetree.ppat_desc = Ppat_var stringLoc})]  when not uncurried ->
      let txtDoc =
        Doc.text (
          if hasConstraint then "(" ^ stringLoc.txt ^ ")" else stringLoc.txt
        )
      in
      printComments txtDoc cmtTbl stringLoc.loc
    (* let f = () => () *)
    | [([], Nolabel, None, {ppat_desc = Ppat_construct({txt = Longident.Lident "()"}, None)})] when not uncurried ->
      Doc.text "()"
    (* let f = (~greeting, ~from as hometown, ~x=?) => () *)
    | parameters ->
      let lparen = if uncurried then Doc.text "(. " else Doc.lparen in
      let shouldHug = ParsetreeViewer.parametersShouldHug parameters in
      let printedParamaters = Doc.concat [
        if shouldHug || inCallback then Doc.nil else Doc.softLine;
        Doc.join ~sep:(Doc.concat [Doc.comma; if inCallback then Doc.space else Doc.line])
          (List.map (fun p -> printExpFunParameter p cmtTbl) parameters)
      ] in
      Doc.group (
        Doc.concat [
          lparen;
          if shouldHug || inCallback then
            printedParamaters
          else Doc.indent printedParamaters;
          if shouldHug || inCallback then
            Doc.nil
          else
            Doc.concat [Doc.trailingComma; Doc.softLine];
          Doc.rparen;
        ]
      )

  and printExpFunParameter (attrs, lbl, defaultExpr, pattern) cmtTbl =
    let (isUncurried, attrs) = ParsetreeViewer.processUncurriedAttribute attrs in
    let uncurried = if isUncurried then Doc.concat [Doc.dot; Doc.space] else Doc.nil in
    let attrs = match attrs with
    | [] -> Doc.nil
    | attrs -> Doc.concat [
      Doc.join ~sep:Doc.line (List.map printAttribute attrs);
      Doc.line;
    ] in
    (* =defaultValue *)
    let defaultExprDoc = match defaultExpr with
    | Some expr -> Doc.concat [
        Doc.text "=";
        printExpressionWithComments expr cmtTbl
      ]
    | None -> Doc.nil
    in
    (* ~from as hometown
     * ~from                   ->  punning *)
    let labelWithPattern = match (lbl, pattern) with
    | (Asttypes.Nolabel, pattern) -> printPattern pattern cmtTbl
    | (
        (Asttypes.Labelled lbl | Optional lbl),
        {ppat_desc = Ppat_var stringLoc}
      ) when lbl = stringLoc.txt ->
        (* ~d *)
        Doc.concat [
          Doc.text "~";
          Doc.text lbl;
        ]
    | (
        (Asttypes.Labelled lbl | Optional lbl),
        ({ppat_desc = Ppat_constraint ({ ppat_desc = Ppat_var { txt } }, _) } as pat)
      ) when lbl = txt ->
        (* ~d: e *)
        Doc.concat [
          Doc.text "~";
          printPattern pat cmtTbl;
        ]
    | ((Asttypes.Labelled lbl | Optional lbl), pattern) ->
        (* ~b as c *)
      Doc.concat [
        Doc.text "~";
        Doc.text lbl;
        Doc.text " as ";
        printPattern pattern cmtTbl
      ]
    in
    let optionalLabelSuffix = match (lbl, defaultExpr) with
    | (Asttypes.Optional _, None) -> Doc.text "=?"
    | _ -> Doc.nil
    in
    let doc = Doc.group (
      Doc.concat [
        uncurried;
        attrs;
        labelWithPattern;
        defaultExprDoc;
        optionalLabelSuffix;
      ]
    ) in
    let cmtLoc = match defaultExpr with
    | None -> pattern.ppat_loc
    | Some expr -> {
      pattern.ppat_loc with loc_end = expr.pexp_loc.loc_end
    } in
    printComments doc cmtTbl cmtLoc

  and printExpressionBlock ~braces expr cmtTbl =
    let rec collectRows acc expr = match expr.Parsetree.pexp_desc with
    | Parsetree.Pexp_letmodule (modName, modExpr, expr2) ->
      let name =
        let doc = Doc.text modName.txt in
        printComments doc cmtTbl modName.loc
      in
      let letModuleDoc = Doc.concat [
        Doc.text "module ";
        name;
        Doc.text " = ";
        printModExpr modExpr cmtTbl;
      ] in
      let loc = {expr.pexp_loc with loc_end = modExpr.pmod_loc.loc_end} in
      collectRows ((loc, letModuleDoc)::acc) expr2
    | Pexp_letexception (extensionConstructor, expr2) ->
      let loc =
        let loc = {expr.pexp_loc with loc_end = extensionConstructor.pext_loc.loc_end} in
        match getFirstLeadingComment cmtTbl loc with
        | None -> loc
        | Some comment ->
          let cmtLoc = Comment.loc comment in
          {cmtLoc with loc_end = loc.loc_end}
      in
      let letExceptionDoc = printExceptionDef extensionConstructor cmtTbl in
      collectRows ((loc, letExceptionDoc)::acc) expr2
    | Pexp_open (overrideFlag, longidentLoc, expr2) ->
      let openDoc = Doc.concat [
        Doc.text "open";
        printOverrideFlag overrideFlag;
        Doc.space;
        printLongidentLocation longidentLoc cmtTbl;
      ] in
      let loc = {expr.pexp_loc with loc_end = longidentLoc.loc.loc_end} in
      collectRows ((loc, openDoc)::acc) expr2
    | Pexp_sequence (expr1, expr2) ->
      let exprDoc =
        let doc = printExpression expr1 cmtTbl in
        match Parens.expr expr1 with
        | Parens.Parenthesized -> addParens doc
        | Braced braces  -> printBraces doc expr1 braces
        | Nothing -> doc
      in
      let loc = expr1.pexp_loc in
      collectRows ((loc, exprDoc)::acc) expr2
    | Pexp_let (recFlag, valueBindings, expr2) ->
      let loc =
        let loc = match valueBindings with
        | [] -> Location.none
        | vb::_ -> vb.pvb_loc
        in
        match getFirstLeadingComment cmtTbl loc with
        | None -> loc
        | Some comment ->
          let cmtLoc = Comment.loc comment in
          {cmtLoc with loc_end = loc.loc_end}
      in
			let recFlag = match recFlag with
			| Asttypes.Nonrecursive -> Doc.nil
			| Asttypes.Recursive -> Doc.text "rec "
			in
      let letDoc = printValueBindings ~recFlag valueBindings cmtTbl in
      (* let () = {
       *   let () = foo()
       *   ()
       * }
       * We don't need to print the () on the last line of the block
       *)
      begin match expr2.pexp_desc with
      | Pexp_construct ({txt = Longident.Lident "()"}, _) ->
        List.rev ((loc, letDoc)::acc)
      | _ ->
        collectRows ((loc, letDoc)::acc) expr2
      end
    | _ ->
      let exprDoc =
        let doc = printExpression expr cmtTbl in
        match Parens.expr expr with
        | Parens.Parenthesized -> addParens doc
        | Braced braces  -> printBraces doc expr braces
        | Nothing -> doc
      in
      List.rev ((expr.pexp_loc, exprDoc)::acc)
    in
    let rows = collectRows [] expr in
    let block =
      printList
        ~getLoc:fst
        ~nodes:rows
        ~print:(fun (_, doc) _ -> doc)
        ~forceBreak:true
        cmtTbl
    in
    Doc.breakableGroup ~forceBreak:true (
      if braces then
        Doc.concat [
          Doc.lbrace;
          Doc.indent (
            Doc.concat [
              Doc.line;
              block;
            ]
          );
          Doc.line;
          Doc.rbrace;
        ]
      else block
    )

  (*
   * // user types:
   * let f = (a, b) => { a + b }
   *
   * // printer: everything is on one line
   * let f = (a, b) => { a + b }
   *
   * // user types: over multiple lines
   * let f = (a, b) => {
   *   a + b
   * }
   *
   * // printer: over multiple lines
   * let f = (a, b) => {
   *   a + b
   * }
   *)
  and printBraces doc expr bracesLoc =
    let overMultipleLines =
      let open Location in
      bracesLoc.loc_end.pos_lnum > bracesLoc.loc_start.pos_lnum
    in
    match expr.Parsetree.pexp_desc with
    | Pexp_letmodule _
    | Pexp_letexception _
    | Pexp_let _
    | Pexp_open _
    | Pexp_sequence _ ->
      (* already has braces *)
      doc
    | _ ->
      Doc.breakableGroup ~forceBreak:overMultipleLines (
        Doc.concat [
          Doc.lbrace;
          Doc.indent (
            Doc.concat [
              Doc.softLine;
              if Parens.bracedExpr expr then addParens doc else doc;
            ]
          );
          Doc.softLine;
          Doc.rbrace;
        ]
      )

  and printOverrideFlag overrideFlag = match overrideFlag with
    | Asttypes.Override -> Doc.text "!"
    | Fresh -> Doc.nil

  and printDirectionFlag flag = match flag with
    | Asttypes.Downto -> Doc.text " downto "
    | Asttypes.Upto -> Doc.text " to "

  and printRecordRow (lbl, expr) cmtTbl =
    let cmtLoc = {lbl.loc with loc_end = expr.pexp_loc.loc_end} in
    let doc = Doc.group (Doc.concat [
      printLongidentLocation lbl cmtTbl;
      Doc.text ": ";
      (let doc = printExpressionWithComments expr cmtTbl in
      match Parens.expr expr with
      | Parens.Parenthesized -> addParens doc
      | Braced braces -> printBraces doc expr braces
      | Nothing -> doc);
    ]) in
    printComments doc cmtTbl cmtLoc

  and printBsObjectRow (lbl, expr) cmtTbl =
    let cmtLoc = {lbl.loc with loc_end = expr.pexp_loc.loc_end} in
    let lblDoc =
      let doc = Doc.concat [
        Doc.text "\"";
        printLongident lbl.txt;
        Doc.text "\"";
      ] in
      printComments doc cmtTbl lbl.loc
    in
    let doc = Doc.concat [
      lblDoc;
      Doc.text ": ";
      printExpressionWithComments expr cmtTbl
    ] in
    printComments doc cmtTbl cmtLoc
  (* The optional loc indicates whether we need to print the attributes in
   * relation to some location. In practise this means the following:
   *  `@attr type t = string` -> on the same line, print on the same line
   *  `@attr
   *   type t = string` -> attr is on prev line, print the attributes
   *   with a line break between, we respect the users' original layout *)
  and printAttributes ?loc (attrs: Parsetree.attributes) =
    match ParsetreeViewer.filterParsingAttrs attrs with
    | [] -> Doc.nil
    | attrs ->
      let lineBreak = match loc with
      | None -> Doc.line
      | Some loc -> begin match List.rev attrs with
        | ({loc = firstLoc}, _)::_ when loc.loc_start.pos_lnum > firstLoc.loc_end.pos_lnum ->
          Doc.hardLine;
        | _ -> Doc.line
        end
      in
      Doc.concat [
        Doc.group (Doc.join ~sep:Doc.line (List.map printAttribute attrs));
        lineBreak;
      ]

  and printAttribute ((id, payload) : Parsetree.attribute) =
      let attrName = Doc.text ("@" ^ id.txt) in
        match payload with
      | PStr [{pstr_desc = Pstr_eval (expr, attrs)}] ->
        let exprDoc = printExpression expr CommentTable.empty in
        let needsParens = match attrs with | [] -> false | _ -> true in
        Doc.group (
          Doc.concat [
            attrName;
            addParens (
              Doc.concat [
                printAttributes attrs;
                if needsParens then addParens exprDoc else exprDoc;
              ]
            )
          ]
        )
      | _ -> attrName

  and printAttributeWithComments ((id, payload) : Parsetree.attribute) cmtTbl =
      let attrName = Doc.text ("@" ^ id.txt) in
      match payload with
      | PStr [{pstr_desc = Pstr_eval (expr, attrs)}] ->
        let exprDoc = printExpressionWithComments expr cmtTbl in
        let needsParens = match attrs with | [] -> false | _ -> true in
        Doc.group (
          Doc.concat [
            attrName;
            addParens (
              Doc.concat [
                printAttributes attrs;
                if needsParens then addParens exprDoc else exprDoc;
              ]
            )
          ]
        )
      | _ -> attrName


  and printModExpr modExpr cmtTbl =
    let doc = match modExpr.pmod_desc with
    | Pmod_ident longidentLoc ->
      printLongidentLocation longidentLoc cmtTbl
    | Pmod_structure structure ->
      Doc.breakableGroup ~forceBreak:true (
        Doc.concat [
          Doc.lbrace;
          Doc.indent (
            Doc.concat [
              Doc.softLine;
              printStructure structure cmtTbl;
            ];
          );
          Doc.softLine;
          Doc.rbrace;
        ]
      )
    | Pmod_unpack expr ->
      let shouldHug = match expr.pexp_desc with
      | Pexp_let _ -> true
      | Pexp_constraint (
          {pexp_desc = Pexp_let _ },
          {ptyp_desc = Ptyp_package packageType}
        ) -> true
      | _ -> false
      in
      let (expr, moduleConstraint) = match expr.pexp_desc with
      | Pexp_constraint (
          expr,
          {ptyp_desc = Ptyp_package packageType; ptyp_loc}
      ) ->
        let packageDoc =
          let doc = printPackageType ~printModuleKeywordAndParens:false packageType cmtTbl in
          printComments doc cmtTbl ptyp_loc
        in
        let typeDoc = Doc.group (Doc.concat [
          Doc.text ":";
          Doc.indent (
            Doc.concat [
              Doc.line;
              packageDoc
            ]
          )
        ]) in
        (expr, typeDoc)
      | _ -> (expr, Doc.nil)
      in
      let unpackDoc = Doc.group(Doc.concat [
        printExpressionWithComments expr cmtTbl;
        moduleConstraint;
      ]) in
      Doc.group (
        Doc.concat [
          Doc.text "unpack(";
          if shouldHug then unpackDoc
          else
            Doc.concat [
              Doc.indent (
                Doc.concat [
                  Doc.softLine;
                  unpackDoc;
                ]
              );
             Doc.softLine;
            ];
          Doc.rparen;
        ]
      )
    | Pmod_extension extension ->
      printExtensionWithComments extension cmtTbl
    | Pmod_apply _ ->
      let (args, callExpr) = ParsetreeViewer.modExprApply modExpr in
      let isUnitSugar = match args with
      | [{pmod_desc = Pmod_structure []}] -> true
      | _ -> false
      in
      let shouldHug = match args with
      | [{pmod_desc = Pmod_structure _}] -> true
      | _ -> false
      in
      Doc.group (
        Doc.concat [
          printModExpr callExpr cmtTbl;
          if isUnitSugar then
            printModApplyArg (List.hd args) cmtTbl
          else
            Doc.concat [
              Doc.lparen;
              if shouldHug then
                printModApplyArg (List.hd args) cmtTbl
              else
                Doc.indent (
                  Doc.concat [
                    Doc.softLine;
                    Doc.join ~sep:(Doc.concat [Doc.comma; Doc.line]) (
                      List.map (fun modArg -> printModApplyArg modArg cmtTbl) args
                    )
                  ]
                );
              if not shouldHug then
                Doc.concat [
                  Doc.trailingComma;
                  Doc.softLine;
                ]
              else Doc.nil;
              Doc.rparen;
            ]
        ]
      )
    | Pmod_constraint (modExpr, modType) ->
      Doc.concat [
        printModExpr modExpr cmtTbl;
        Doc.text ": ";
        printModType modType cmtTbl;
      ]
    | Pmod_functor _ ->
      printModFunctor modExpr cmtTbl
    in
    printComments doc cmtTbl modExpr.pmod_loc

  and printModFunctor modExpr cmtTbl =
    let (parameters, returnModExpr) = ParsetreeViewer.modExprFunctor modExpr in
    (* let shouldInline = match returnModExpr.pmod_desc with *)
    (* | Pmod_structure _ | Pmod_ident _ -> true *)
    (* | Pmod_constraint ({pmod_desc = Pmod_structure _}, _) -> true *)
    (* | _ -> false *)
    (* in *)
    let (returnConstraint, returnModExpr) = match returnModExpr.pmod_desc with
    | Pmod_constraint (modExpr, modType) ->
      let constraintDoc =
        let doc = printModType modType cmtTbl in
        if Parens.modExprFunctorConstraint modType then addParens doc else doc
      in
      let modConstraint = Doc.concat [
        Doc.text ": ";
        constraintDoc;
      ] in
      (modConstraint, printModExpr modExpr cmtTbl)
    | _ -> (Doc.nil, printModExpr returnModExpr cmtTbl)
    in
    let parametersDoc = match parameters with
    | [(attrs, {txt = "*"}, None)] ->
        let attrs = match attrs with
        | [] -> Doc.nil
        | attrs -> Doc.concat [
          Doc.join ~sep:Doc.line (List.map printAttribute attrs);
          Doc.line;
        ] in
        Doc.group (Doc.concat [
          attrs;
          Doc.text "()"
        ])
    | [([], {txt = lbl}, None)] -> Doc.text lbl
    | parameters ->
      Doc.group (
        Doc.concat [
          Doc.lparen;
          Doc.indent (
            Doc.concat [
              Doc.softLine;
              Doc.join ~sep:(Doc.concat [Doc.comma; Doc.line]) (
                List.map (fun param -> printModFunctorParam param cmtTbl) parameters
              )
            ]
          );
          Doc.trailingComma;
          Doc.softLine;
          Doc.rparen;
        ]
      )
    in
    Doc.group (
      Doc.concat [
        parametersDoc;
        returnConstraint;
        Doc.text " => ";
        returnModExpr
      ]
    )

  and printModFunctorParam (attrs, lbl, optModType) cmtTbl =
    let cmtLoc = match optModType with
    | None -> lbl.Asttypes.loc
    | Some modType -> {lbl.loc with loc_end =
        modType.Parsetree.pmty_loc.loc_end
      }
    in
    let attrs = match attrs with
    | [] -> Doc.nil
    | attrs -> Doc.concat [
      Doc.join ~sep:Doc.line (List.map printAttribute attrs);
      Doc.line;
    ] in
    let lblDoc =
      let doc = Doc.text lbl.txt in
      printComments doc cmtTbl lbl.loc
    in
    let doc = Doc.group (
      Doc.concat [
        attrs;
        lblDoc;
        (match optModType with
        | None -> Doc.nil
        | Some modType ->
          Doc.concat [
            Doc.text ": ";
            printModType modType cmtTbl
          ]);
      ]
    ) in
    printComments doc cmtTbl cmtLoc

  and printModApplyArg modExpr cmtTbl =
    match modExpr.pmod_desc with
    | Pmod_structure [] -> Doc.text "()"
    | _ -> printModExpr modExpr cmtTbl


  and printExceptionDef (constr : Parsetree.extension_constructor) cmtTbl =
    let kind = match constr.pext_kind with
    | Pext_rebind longident -> Doc.indent (
        Doc.concat [
          Doc.text " =";
          Doc.line;
          printLongidentLocation longident cmtTbl;
        ]
     )
    | Pext_decl (Pcstr_tuple [], None) -> Doc.nil
    | Pext_decl (args, gadt) ->
      let gadtDoc = match gadt with
      | Some typ -> Doc.concat [
          Doc.text ": ";
          printTypExpr typ cmtTbl
        ]
      | None -> Doc.nil
      in
      Doc.concat [
        printConstructorArguments ~indent:false args cmtTbl;
        gadtDoc
      ]
    in
    let name =
      printComments
        (Doc.text constr.pext_name.txt)
        cmtTbl
        constr.pext_name.loc
    in
    let doc = Doc.group (
      Doc.concat [
        printAttributes constr.pext_attributes;
        Doc.text "exception ";
        name;
        kind
      ]
    ) in
    printComments doc cmtTbl constr.pext_loc

  and printExtensionConstructor (constr : Parsetree.extension_constructor) cmtTbl i =
    let attrs = printAttributes constr.pext_attributes in
    let bar = if i > 0 then Doc.text "| "
      else Doc.ifBreaks (Doc.text "| ") Doc.nil
    in
    let kind = match constr.pext_kind with
    | Pext_rebind longident -> Doc.indent (
        Doc.concat [
          Doc.text " =";
          Doc.line;
          printLongidentLocation longident cmtTbl;
        ]
     )
    | Pext_decl (Pcstr_tuple [], None) -> Doc.nil
    | Pext_decl (args, gadt) ->
      let gadtDoc = match gadt with
      | Some typ -> Doc.concat [
          Doc.text ": ";
          printTypExpr typ cmtTbl;
        ]
      | None -> Doc.nil
      in
      Doc.concat [
        printConstructorArguments ~indent:false args cmtTbl;
        gadtDoc
      ]
    in
    let name =
      printComments (Doc.text constr.pext_name.txt) cmtTbl constr.pext_name.loc
    in
    Doc.concat [
      bar;
      Doc.group (
        Doc.concat [
          attrs;
          name;
          kind;
        ]
      )
    ]

  let printImplementation ~width (s: Parsetree.structure) comments =
    let cmtTbl = CommentTable.make () in
    CommentTable.walkStructure s cmtTbl comments;
    (* CommentTable.log cmtTbl; *)
    let doc = printStructure s cmtTbl in
    (* Doc.debug doc; *)
    let stringDoc = Doc.toString ~width doc in
    print_string stringDoc

  let printInterface ~width (s: Parsetree.signature) comments =
    let cmtTbl = CommentTable.make () in
    CommentTable.walkSignature s cmtTbl comments;
    let stringDoc = Doc.toString ~width (printSignature s cmtTbl) in
    print_string stringDoc

end
