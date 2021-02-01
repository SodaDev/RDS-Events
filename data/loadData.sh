curl https://services-api.ryanair.com/locate/3/routes | jq -r '.[] | [
  .airportFrom,
  .airportTo,
  .connectingAirport,
  .newRoute,
  .seasonalRoute,
  .operator,
  .group,
  ( [ .tags[]] | join(";") ),
  ( [ .similarArrivalAirportCodes[]] | join(",") ),
  .carrierCode
] | @csv' > routes.csv