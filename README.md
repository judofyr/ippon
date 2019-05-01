# Ippon: Web development the gentle way

Ippon is a library of small modules (50 to 500 lines of code) which are useful
for web development.

Under development:

- {Ippon::Migrator}: Migration system built on Sequel.
- {Ippon::Validate}: Form validation.
- {Ippon::FormData}: Type-safe interface to form data.
- {Ippon::Paginator}: Calculates pagination information.

## Features

- Framework-agnostic. Works whether you use Rails, Sinatra, Roda, Hanami or Camping.
- Well-documented public API with stable versioning.
- Modules are object-oriented, not DSL magic.
- Modules are mostly independent of each other. You don't need to understand
  everything in Ippon to use one part.
- 100% test coverage. 100% documentation coverage.
- No dependencies. (Although some modules integrate with other gems.)
- Cross-platform forever. No C/Java extensions.

## Versioning

Ippon is currently not yet released.

## License

Ippon is is available under the 0BSD license:

> Copyright (C) 2018 Magnus Holm <judofyr@gmail.com>
>
> Permission to use, copy, modify, and/or distribute this software for any
> purpose with or without fee is hereby granted.
>
> THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
> REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
> AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
> INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
> LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
> OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
> PERFORMANCE OF THIS SOFTWARE.
