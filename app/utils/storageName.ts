// A file name as it goes into a storage key. The storage server reads the key like a URL path: a name with a literal
// "%28" (copied from a link or an email) is saved as "(", while the key we keep in the database still says "%28", so the
// file can never be found again. Characters that mean something in a URL are replaced; the name shown to people is the original.
export const storageSafeName = (name: string) => name.replace(/[%#?\\\u0000-\u001F]/g, "_");
