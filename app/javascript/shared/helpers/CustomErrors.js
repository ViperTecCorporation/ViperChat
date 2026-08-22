/* eslint-disable max-classes-per-file */
export class DuplicateContactException extends Error {
  static DEFAULT_MESSAGE = 'DUPLICATE_CONTACT';

  constructor(data) {
    super(DuplicateContactException.DEFAULT_MESSAGE);
    this.data = data;
    this.name = 'DuplicateContactException';
  }

  /** Server or client may assign `message` after construction; otherwise still DEFAULT_MESSAGE. */
  get contactErrorDetail() {
    return this.message === DuplicateContactException.DEFAULT_MESSAGE
      ? null
      : this.message;
  }

  get contactErrorAttributes() {
    if (Array.isArray(this.data)) return this.data;
    if (typeof this.data === 'string') return [this.data];
    if (!this.data || typeof this.data !== 'object') return [];
    if (Array.isArray(this.data.attributes)) return this.data.attributes;

    return Object.keys(this.data);
  }
}
export class ExceptionWithMessage extends Error {
  constructor(data) {
    super('ERROR_WITH_MESSAGE');
    this.data = data;
    this.name = 'ExceptionWithMessage';
  }
}
