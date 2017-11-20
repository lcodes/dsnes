/**
 * Native File Dialog
 * User API
 * http://www.frogtoss.com/labs
 */
module nfd;

public {
  import core.stdc.stdlib : free;

  import std.conv : to;
}

/* denotes UTF-8 char */
alias nfdchar_t = char;

/* opaque data structure -- see NFD_PathSet_* */
struct nfdpathset_t {
  nfdchar_t* buf;
  size_t* indices; /* byte offsets into buf */
  size_t count;    /* number of indices into buf */
}

alias nfdresult_t = int;
enum {
  NFD_ERROR,
  NFD_OKAY,
  NFD_CANCEL
}

extern (C) nothrow @nogc:

/* nfd_<targetplatform>.c */

/* single file open dialog */
nfdresult_t NFD_OpenDialog(in nfdchar_t* filterList,
                           in nfdchar_t* defaultPath,
                           nfdchar_t** outPath);

/* multiple file open dialog */
nfdresult_t NFD_OpenDialogMultiple(in nfdchar_t* filterList,
                                   in nfdchar_t* defaultPath,
                                   nfdpathset_t* outPaths);

/* save dialog */
nfdresult_t NFD_SaveDialog(in nfdchar_t* filterList,
                           in nfdchar_t* defaultPath,
                           nfdchar_t** outPath);


/* select folder dialog */
nfdresult_t NFD_PickFolder(in nfdchar_t* defaultPath,
                           nfdchar_t** outPath);

/* nfd_common.c */

/* get last error -- set when nfdresult_t returns NFD_ERROR */
const(char)* NFD_GetError();
/* get the number of entries stored in pathSet */
size_t      NFD_PathSet_GetCount(in nfdpathset_t* pathSet );
/* Get the UTF-8 path at offset index */
nfdchar_t  *NFD_PathSet_GetPath(in nfdpathset_t* pathSet, size_t index);
/* Free the pathSet */
void        NFD_PathSet_Free(nfdpathset_t* pathSet);
