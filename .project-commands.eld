;;; -*- lisp-data -*-
((run . "nim r src/ellipse/gltf.nim")
 (commands "nim r src/ellipse/application.nim" "nim r src/ellipse"
	   "nim r src/rendering/cameras.nim"
	   "nim r src/ellipse/gltf.nim"))
