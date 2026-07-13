namespace GDiagram {
    /**
     * Whether two File objects name the same file, so opening a file that is already
     * open focuses its tab instead of adding a second one.
     *
     * Files that exist compare by the filesystem's file id (device + inode), which also
     * matches a path through a symlink or a hard link. Otherwise the paths are
     * canonicalized ("." and ".." removed, relative paths made absolute) and compared.
     */
    public class PathIdentity {
        public static string key(File file) {
            try {
                var info = file.query_info(FileAttribute.ID_FILE, FileQueryInfoFlags.NONE, null);
                string? id = info.get_attribute_string(FileAttribute.ID_FILE);
                if (id != null && id.length > 0) return "id:" + id;
            } catch (Error e) {
                // Not on disk (any more): fall back to the path
            }
            string? path = file.get_path();
            if (path != null) return "path:" + Filename.canonicalize(path, null);
            return "uri:" + file.get_uri();
        }

        public static bool same_file(File a, File b) {
            if (a.equal(b)) return true;
            return key(a) == key(b);
        }

        // Index of the entry naming the same file as `file`, or -1 (null entries: unsaved)
        public static int index_of(Gee.List<File?> files, File file) {
            string? file_key = null;
            for (int i = 0; i < files.size; i++) {
                var other = files[i];
                if (other == null) continue;
                if (other.equal(file)) return i;
                if (file_key == null) file_key = key(file);
                if (key(other) == file_key) return i;
            }
            return -1;
        }
    }
}
