// Petit programme d'essai du kit Go : `commencer` puis `terminer`.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/url"
	"os"

	dropletid "github.com/rito27959-arch/droplet/droplet-id/kits/go"
)

func main() {
	ctx := context.Background()
	a := os.Args[1:]
	d, err := dropletid.Nouveau(ctx, dropletid.Options{Emetteur: a[0], ClientID: a[1], RedirectURI: a[2], Portees: []string{"openid", "profile"}})
	if err != nil {
		panic(err)
	}
	if a[3] == "commencer" {
		u, at := d.Commencer()
		b, _ := json.Marshal(map[string]any{"url": u, "attente": at})
		fmt.Println(string(b))
		return
	}
	var at dropletid.Attente
	_ = json.Unmarshal([]byte(a[5]), &at)
	u, _ := url.Parse(a[4])
	s, err := d.Terminer(ctx, u.Query(), at)
	if err != nil {
		panic(err)
	}
	b, _ := json.Marshal(map[string]string{"sub": s.Sub, "pseudo": s.Pseudo})
	fmt.Println(string(b))
}
