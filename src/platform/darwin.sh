display_qr() {
	  if type imgcat >/dev/null 2>&1; then
		    echo -n "$1" | qrencode --size 10 -o - | imgcat
	  else
		    echo -n "$1" | qrencode -t utf8
	  fi
}
