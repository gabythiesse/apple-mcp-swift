// Statut TCC Contacts du binaire (sans demande) : 0 non déterminé, 1 restreint, 2 refusé, 3 autorisé
import Contacts
relancerResponsable()
print("statut Contacts:", CNContactStore.authorizationStatus(for: .contacts).rawValue)
