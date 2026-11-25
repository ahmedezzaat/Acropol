// A file name as it goes into a storage key. The storage server only accepts a limited set of characters in a key
// (English letters, digits and a few signs): a name with Arabic letters is refused ("Invalid key"), and one with a
// literal "%28" (copied from a link) is saved under a different key than the one we keep. So the key gets a plain
// version of the name (the extension kept, anything else becomes "_"); the name shown to people, and the name a
// downloaded file gets, is the original one kept in the file_name column.
export const storageSafeName = (name: string) => {
  const dot = name.lastIndexOf(".");
  const ext = dot > 0 ? name.slice(dot + 1).replace(/[^A-Za-z0-9]/g, "").slice(0, 10).toLowerCase() : "";
  const base = (dot > 0 ? name.slice(0, dot) : name)
    .replace(/[^A-Za-z0-9._() -]+/g, "_")
    .replace(/_{2,}/g, "_")
    .replace(/^[_ .-]+|[_ .-]+$/g, "")
    .slice(0, 80);
  // a name that was only Arabic letters leaves nothing: a short random part keeps the key unique and readable enough
  const safe = base || `file-${Math.random().toString(36).slice(2, 8)}`;
  return ext ? `${safe}.${ext}` : safe;
};
