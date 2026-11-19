#!/bin/sh

set -eu

cd "$(dirname "$0")/../.."
if [ -z "${PROTOC:-}" ]; then
    swift build --product protoc
    PROTOC="$(swift build --show-bin-path)/protoc"
fi

protos=Tests/Fixtures/protos
out=Tests/SwiftProtoGenTests/Descriptors

"$PROTOC" -I "$protos" --include_imports --include_source_info \
    --descriptor_set_out="$out/person.pb" example/person.proto
"$PROTOC" -I "$protos" --descriptor_set_out="$out/item.pb" inventory/item.proto
"$PROTOC" -I "$protos" --include_imports --descriptor_set_out="$out/widget.pb" editions/widget.proto
