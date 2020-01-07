# Copyright 2020 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


# Start by building the application.
FROM golang:1.13 AS build
WORKDIR /src/main
COPY main.go go.mod go.sum ./
RUN go mod download
RUN CGO_ENABLED=0 go install -a -tags netgo -ldflags=-w

# Now copy it into our base image.
FROM gcr.io/distroless/base
COPY --from=build /go/bin/main /bin/main
ENTRYPOINT [ "/bin/main" ]
CMD ["1"]
