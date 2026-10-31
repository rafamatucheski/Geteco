extends RefCounted
## Nomes/origens dos produtos: catálogo público da Curitiba Cellar, conferido em 2026-10-07.
## Preços, cura, doses e embriaguez são regras fictícias do jogo.
const SERVINGS := 3
const ORDER := ["zacharias_nemea", "zacharias_malagousia", "ag_chardonnay", "ag_festividad", "medeiros_private", "medeiros_rose", "ancla_cabernet", "ancla_merlot"]
const COUNTRIES := ["Grécia", "Brasil", "Portugal", "Chile"]
const WINES := {
	"zacharias_nemea":{"name":"Zacharias Nemea", "country":"Grécia", "grape":"Agiorgitiko", "style":"Tinto", "price":145, "heal":16, "alcohol":27.0, "color":Color("7c213b"), "source":"https://www.curitibacellar.com.br/product-page/zacharias-nemea-2022"},
	"zacharias_malagousia":{"name":"Zacharias Malagousia", "country":"Grécia", "grape":"Malagousia", "style":"Branco", "price":115, "heal":13, "alcohol":23.0, "color":Color("d8c884"), "source":"https://www.curitibacellar.com.br/product-page/zacharias-malagousia-2022"},
	"ag_chardonnay":{"name":"AG Chardonnay Carvalho", "country":"Brasil", "grape":"Chardonnay", "style":"Branco", "price":125, "heal":14, "alcohol":24.0, "color":Color("d6ae5d"), "source":"https://www.curitibacellar.com.br/product-page/ag-chardonnay-carvalho"},
	"ag_festividad":{"name":"AG Espumante Festividad", "country":"Brasil", "grape":"Chardonnay · Pinot Noir", "style":"Espumante", "price":85, "heal":12, "alcohol":23.0, "color":Color("cbcd91"), "source":"https://www.curitibacellar.com.br/product-page/ag-espumante-festividad"},
	"medeiros_private":{"name":"Medeiros Private Selection", "country":"Portugal", "grape":"Touriga Nacional · corte tinto", "style":"Tinto", "price":155, "heal":17, "alcohol":27.0, "color":Color("82223c"), "source":"https://www.curitibacellar.com.br/product-page/medeirosprivate-selection"},
	"medeiros_rose":{"name":"Medeiros Regional Rosé", "country":"Portugal", "grape":"Touriga Nacional · Syrah · Aragonez", "style":"Rosé", "price":95, "heal":13, "alcohol":24.0, "color":Color("d78a83"), "source":"https://www.curitibacellar.com.br/product-page/medeiros-regional-ros%C3%A9"},
	"ancla_cabernet":{"name":"ANCLA Reserva Cabernet Sauvignon", "country":"Chile", "grape":"Cabernet Sauvignon", "style":"Tinto", "price":75, "heal":12, "alcohol":27.0, "color":Color("702139"), "source":"https://www.curitibacellar.com.br/product-page/ancla-reserva-cabernet-sauvignon"},
	"ancla_merlot":{"name":"ANCLA Gran Reserva Merlot", "country":"Chile", "grape":"Merlot · Syrah", "style":"Tinto", "price":100, "heal":14, "alcohol":27.0, "color":Color("883241"), "source":"https://www.curitibacellar.com.br/product-page/ancla-gran-reserva-merlot"},
}
static func spec(id: String) -> Dictionary:
	return WINES.get(id,{}).duplicate(true)
