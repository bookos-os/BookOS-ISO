# BookOS Dev ISO — bleeding edge, unstable
%include bookos-base.ks
# /repo/fedora/<ver>/<arch>/<canal>/ nunca existió en el servidor: en modo
# SERVIDOR (NO_LOCAL_REPO=1) el build pedía un repo 404. Hoy el único repo es
# /store-files/. La línea se mantiene porque build-iso.sh la reescribe a
# file:// en modo LOCAL buscando `repo --name=bookos `.
repo --name=bookos --baseurl=https://bookos.es/store-files/ --cost=10
