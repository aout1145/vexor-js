import { TTY, mode } from 'std:internal:tty';

const stdin = new TTY(0);
const stdout = new TTY(1);
const stderr = new TTY(2);

export { TTY, mode, stdin, stdout, stderr };