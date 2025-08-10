import { sleep, Timer } from 'std:internal:timer';

function setTimer(...args) {
    return new Timer(...args);
}

export { sleep, setTimer };
