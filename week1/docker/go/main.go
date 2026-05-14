package main
import (
    "fmt"
    "net/http"
)
func main() {
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        fmt.Fprintf(w, "<h1>Hello world from Go server</h1>\n")
    })
    http.ListenAndServe(":8080", nil)
}
