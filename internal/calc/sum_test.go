package calc

import "testing"

// TestSum usa el patrón idiomático de Go para tests: "table-driven tests".
// En vez de escribir una función de test por caso, definimos una tabla de casos
// y los recorremos. Agregar un caso nuevo = agregar una fila.
func TestSum(t *testing.T) {
	casos := []struct {
		nombre   string
		a, b     int
		esperado int
	}{
		{"positivos", 2, 3, 5},
		{"con cero", 0, 7, 7},
		{"negativos", -4, -6, -10},
		{"signos mezclados", -5, 5, 0},
	}

	for _, c := range casos {
		// t.Run crea un subtest por caso: si uno falla, el output dice exactamente
		// cuál (por su nombre), no solo "TestSum falló".
		t.Run(c.nombre, func(t *testing.T) {
			obtenido := Sum(c.a, c.b)
			if obtenido != c.esperado {
				t.Errorf("Sum(%d, %d) = %d; se esperaba %d", c.a, c.b, obtenido, c.esperado)
			}
		})
	}
}
