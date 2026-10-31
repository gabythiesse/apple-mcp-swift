// Lanceur stable du serveur MCP Contacts.
// macOS lie les autorisations Contacts et Automatisation à l'identité de CE binaire (signature ad hoc = son empreinte).
// Il est minuscule et ne change pas : toute la logique est dans libContactsMCPCore.dylib, posée à côté,
// qu'on peut reconstruire sans que macOS redemande les autorisations.
import Darwin

var buf = [CChar](repeating: 0, count: 4096)
let exe = proc_pidpath(getpid(), &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : CommandLine.arguments[0]
let lib = String(exe[..<(exe.lastIndex(of: "/") ?? exe.startIndex)]) + "/libContactsMCPCore.dylib"
guard let h = dlopen(lib, RTLD_NOW), let entry = dlsym(h, "contacts_mcp_main") else {
    fputs("[contacts-mcp] chargement impossible de \(lib) : \(dlerror().map { String(cString: $0) } ?? "?")\n", stderr)
    exit(1)
}
unsafeBitCast(entry, to: (@convention(c) () -> Void).self)()
