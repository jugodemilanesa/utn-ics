module github.com/jugodemilanesa/utn-ics

go 1.25.0

// Toolchain pineada al patch exacto: builds reproducibles y stdlib parcheada.
// Go 1.22 era EOL (govulncheck reportaba 29 vulns de stdlib alcanzables); 1.25.11
// las limpia. GOTOOLCHAIN=auto (default) baja esta version sola si no la tenes.
toolchain go1.25.11
