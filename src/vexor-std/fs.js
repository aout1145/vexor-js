import * as internal from 'std:internal:fs';

export const constants = internal.constants;

function convertFlags(flags) {
    if (typeof flags === 'number') {
        return flags;
    }
    switch (flags) {
        case 'a': return constants.O_APPEND | constants.O_CREAT | constants.O_WRONLY;
        case 'ax': return constants.O_APPEND | constants.O_CREAT | constants.O_WRONLY | constants.O_EXCL;
        case 'a+': return constants.O_APPEND | constants.O_CREAT | constants.O_RDWR;
        case 'ax+': return constants.O_APPEND | constants.O_CREAT | constants.O_RDWR | constants.O_EXCL;
        case 'as': return constants.O_APPEND | constants.O_CREAT | constants.O_WRONLY | constants.O_SYNC;
        case 'as+': return constants.O_APPEND | constants.O_CREAT | constants.O_RDWR | constants.O_SYNC;
        case 'r': return constants.O_RDONLY;
        case 'rs': return constants.O_RDONLY | constants.O_SYNC;
        case 'r+': return constants.O_RDWR;
        case 'rs+': return constants.O_RDWR | constants.O_SYNC;
        case 'w': return constants.O_TRUNC | constants.O_CREAT | constants.O_WRONLY;
        case 'wx': return constants.O_TRUNC | constants.O_CREAT | constants.O_WRONLY | constants.O_EXCL;
        case 'w+': return constants.O_TRUNC | constants.O_CREAT | constants.O_RDWR;
        case 'wx+': return constants.O_TRUNC | constants.O_CREAT | constants.O_RDWR | constants.O_EXCL;
        default:
            throw new RangeError(`Unknown file flag: ${flags}`);
    }
}

class File extends internal.File {
    read(length, offset = -1) {
        return super.read(length, offset);
    }
    write(buffer, offset = -1) {
        return super.write(buffer, offset);
    }
}
const Dir = internal.Dir;

export async function open(path, flags = 'r', mode = 0o666) {
    return new File(await internal.open(path, convertFlags(flags), mode));
}
export async function mkstemp(tpl) {
    const { path, fd } = await internal.mkstemp(tpl);
    return {
        path: path,
        file: new File(fd),
    };
}
export async function opendir(path) {
    return new Dir(await internal.opendir(path));
}
export function access(path, mode = constants.F_OK) {
    return internal.access(path, mode);
}
export function copyfile(src, dest, flags = constants.COPYFILE_EXCL) {
    return internal.copyfile(src, dest, flags);
}
export function mkdir(path, mode = 0o777) {
    return internal.mkdir(path, mode);
}
export function symlink(target, path, flags = 0) {
    return internal.symlink(target, path, flags);
}
export function sendfile(out_file, in_file, in_offset = 0, length = 0) {
    if (!(out_file instanceof File) || !(in_file instanceof File)) {
        throw new TypeError('not a File');
    }
    return internal.sendfile(out_file.fd, in_file.fd, in_offset, length);
}
export function scandir(flags = 0) {
    return internal.scandir(flags);
}
export const unlink = internal.unlink;
export const mkdtemp = internal.mkdtemp;
export const rmdir = internal.rmdir;
export const stat = internal.stat;
export const rename = internal.rename;
export const chmod = internal.chmod;
export const utime = internal.utime;
export const lutime = internal.lutime;
export const lstat = internal.lstat;
export const link = internal.link;
export const readlink = internal.readlink;
export const realpath = internal.realpath;
export const chown = internal.chown;
export const lchown = internal.lchown;
export const statfs = internal.statfs;

export async function exists(path) {
    try {
        await access(path);
        return true;
    } catch (e) {
        return false;
    }
}

export const getcwd = internal.getcwd;
export const chdir = internal.chdir;
export const gethomedir = internal.gethomedir;
export const gettmpdir = internal.gettmpdir;