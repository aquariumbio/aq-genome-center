# typed: false
# frozen_string_literal: true

needs 'Standard Libs/Units'
needs 'Standard Libs/CommonInputOutputNames'
needs 'Covid Surveillance/SampleConstants'

module AnnealRNACompositionDefinitions
  include Units
  include CommonInputOutputNames
  include SampleConstants

  AREA_SEAL = "Microseal 'B' adhesive seals"
  ANNEAL_KIT = 'Anneal RNA Kit'

  EPH_HT = 'EPH3 HT'

  def components
    [ 
       {
         input_name: POOLED_PLATE,
         qty: 8.5, units: MICROLITERS,
         sample_name: 'Pooled Specimens',
         object_type: '96-Well Plate'
       }
    ]
  end

  def consumables
    [
      {
        input_name: AREA_SEAL,
        qty: 1, units: 'Each',
        description: 'Adhesive Plate Seal'
      }
    ]
  end

  def kits
    [
      {
        input_name: ANNEAL_KIT,
        qty: 1, units: 'kits',
        description: 'RNA Annealing Kit',
        location: 'M80 Freezer',
        components: [
          {
           input_name: EPH_HT,
           qty: 8.5, units: MICROLITERS,
           sample_name: 'Elution Prime Fragment 3HC Mix',
           object_type: 'Reagent Bottle'
          }
        ],
        consumables: [
        ]
      }
    ]
  end
end