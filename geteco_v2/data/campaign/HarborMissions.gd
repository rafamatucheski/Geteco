extends RefCounted
## Original Harbor IDs/order/rewards. Events are V2 adapters to original actions.
## Source: HarborFirstFavors, HarborStoryTow, CobraCampaignController/State.
const ORDER := ["primeiro_giro", "cobra_contact", "cobra_race", "cobra_collection", "cobra_supply", "cobra_finale"]
const MISSIONS := {
	"primeiro_giro": {"title": "Primeiro Giro", "reward": 150, "requires": "", "hour": 10,
		"steps": [
			{"event": "bank_receipt_received", "target": "helena", "objective": "Vá ao Banco North Pier. Guarde a arma e fale com Helena para retirar o comprovante.", "on_foot": true, "unarmed": true},
			{"event": "harbor_parcel_collected", "target": "harbor_parcel", "objective": "Vá ao porto. A pé, use a interação junto à encomenda para retirar a peça paga.", "on_foot": true},
			{"event": "maciota_delivery_received", "target": "maciota", "objective": "Volte à garagem e fale com Maciota para entregar a peça.", "on_foot": true}],
		"sets_flags": ["harbor_delivery_complete"], "source": "world/harbor/campaign/HarborFirstFavors.gd"},
	"cobra_contact": {"title": "Dentro do território", "reward": 120, "requires": "primeiro_giro", "hour": 15,
		"steps": [
			{"event": "ferrugem_met", "target": "ferrugem", "objective": "Converse com Ferrugem na oficina dos Cobras.", "on_foot": true},
			{"event": "story_vehicle_loaded", "target": "story_tow_vehicle", "objective": "Use o guincho do Neco para carregar o carro da cliente.", "vehicle_action": true},
			{"event": "story_vehicle_unloaded", "target": "neco_bay", "objective": "Leve o carro à baia do Neco e descarregue.", "vehicle_action": true},
			{"event": "neco_repair_received", "target": "neco", "objective": "Fale com Neco para entregar o carro para reparo.", "on_foot": true, "no_wanted": true},
			{"event": "ferrugem_work_order_received", "target": "ferrugem", "objective": "Leve a via da ordem de serviço ao Ferrugem.", "on_foot": true}],
		"sets_flags": ["cobra_contact_complete"], "source": "world/harbor/campaign/HarborStoryTow.gd"},
	"cobra_race": {"title": "Prova de rua", "reward": 200, "requires": "cobra_contact", "hour": 21,
		"steps": [
			{"event": "race_started", "target": "ashbend_start", "objective": "Pare na largada de Ashbend, aponte o carro para o norte e use a interação.", "in_vehicle": true},
			{"event": "race_checkpoint", "target": "ashbend_gate_0", "objective": "Passe pelo primeiro portão.", "checkpoint": 0, "in_vehicle": true},
			{"event": "race_checkpoint", "target": "ashbend_gate_1", "objective": "Passe pelo segundo portão.", "checkpoint": 1, "in_vehicle": true},
			{"event": "race_checkpoint", "target": "ashbend_gate_2", "objective": "Passe pelo terceiro portão.", "checkpoint": 2, "in_vehicle": true},
			{"event": "race_checkpoint", "target": "ashbend_gate_3", "objective": "Passe pelo quarto portão.", "checkpoint": 3, "in_vehicle": true},
			{"event": "race_finished", "target": "ashbend_finish", "objective": "Conclua a prova em até 100 segundos.", "in_vehicle": true}],
		"sets_flags": ["cobra_race_complete"], "source": "world/harbor/campaign/CobraCampaignController.gd"},
	"cobra_collection": {"title": "A conta chega", "reward": 250, "requires": "cobra_race", "hour": -1,
		"steps": [
			{"event": "resident_met", "target": "ashbend_resident", "objective": "Converse com a moradora de Ashbend.", "on_foot": true},
			{"event": "ambush_cleared", "target": "resident_encounter", "objective": "Proteja a moradora da cobrança dos Cobras.", "encounter": true},
			{"event": "resident_saved", "target": "ashbend_resident", "objective": "Converse novamente com a moradora.", "on_foot": true}],
		"sets_flags": ["cobra_collection_complete"], "source": "world/harbor/campaign/CobraCampaignController.gd"},
	"cobra_supply": {"title": "Cortar o abastecimento", "reward": 350, "requires": "cobra_collection", "hour": -1,
		"steps": [
			{"event": "supply_reached", "target": "cobra_supply", "objective": "Vá aos fundos da quadra dos Cobras.", "on_foot": true},
			{"event": "supply_encounter_cleared", "target": "supply_encounter", "objective": "Enfrente os cobradores e recupere os registros.", "encounter": true},
			{"event": "supply_records_collected", "target": "cobra_supply", "objective": "Recolha os registros de carga.", "on_foot": true}],
		"sets_flags": ["cobra_supply_complete"], "source": "world/harbor/campaign/CobraCampaignController.gd"},
	"cobra_finale": {"title": "A última cobrança", "reward": 600, "requires": "cobra_supply", "hour": -1,
		"steps": [
			{"event": "workshop_reached", "target": "ferrugem", "objective": "Vá à oficina da liderança dos Cobras.", "on_foot": true},
			{"event": "boss_encounter_cleared", "target": "boss_encounter", "objective": "Enfrente a liderança dos Cobras.", "encounter": true},
			{"event": "transfer_document_collected", "target": "transfer_document", "objective": "Procure o documento que liga Vicente à transferência.", "on_foot": true}],
		"sets_flags": ["cobra_defeated"], "source": "world/harbor/campaign/CobraCampaignController.gd"}
}
