# typed: false
# frozen_string_literal: true

needs 'Standard Libs/PlanParams'
needs 'Standard Libs/Debug'
needs 'Standard Libs/InstrumentHelper'
needs 'Standard Libs/ItemActions'
needs 'Standard Libs/UploadHelper'
needs 'Small Instruments/Centrifuges'
needs 'Small Instruments/Shakers'
needs 'Standard Libs/Units'
needs 'Covid Surveillance/SampleConstants'
needs 'Covid Surveillance/AssociationKeys'
needs 'Covid Surveillance/CovidSurveillanceHelper'
needs 'Liquid Robot Helper/RobotHelper'

needs 'Composition Libs/Composition'
needs 'CompositionLibs/CompositionHelper'

needs 'Collection Management/CollectionTransfer'
needs 'Collection Management/CollectionActions'

needs 'Kits/KitContents'

needs 'Consumable Libs/Consumables'
needs 'Consumable Libs/ConsumableDefinitions'

class Protocol
  include PlanParams
  include Debug
  include InstrumentHelper
  include ItemActions
  include UploadHelper
  include Centrifuges
  include Shakers
  include Units
  include SampleConstants
  include AssociationKeys
  include RobotHelper
  include CompositionHelper
  include CollectionTransfer
  include CollectionActions
  include CovidSurveillanceHelper
  include KitContents
  include ConsumableDefinitions

 #========== Composition Definitions ==========#

  COMPOSITION_KEY = 'composition'

  POOLED_LIBRARY = 'Pooled Library'
  KIT_SAMPLE_NAME = 'dsDNA HS Assay Kit'
  def components
    [ 
      {
        input_name: POOLED_LIBRARY,
        qty: 10, units: MICROLITERS,
        sample_name: nil,
        suggested_ot: nil
      },
      {
        input_name: MASTER_MIX,
        qty: 180, units: MICROLITERS,
        sample_name: MASTER_MIX,
        suggested_ot: 'Reagent Bottle'
     },
     {
       input_name: RSB_HT,
       qty: nil, units: MICROLITERS,
       sample_name: RSB_HT,
       suggested_ot: 'Reagent Bottle',
       notes: 'Thaw and Keep on Ice'
    },
    ]
  end

  def consumable_data
    [
      {
        consumable: CONSUMABLES[TEST_TUBE],
        qty: 1, units: 'Each'
      },
      {
        consumable: CONSUMABLES[MICRO_TUBE],
        qty: 1, units: 'Each'
      }
    ]
  end

########## DEFAULT PARAMS ##########

# Default parameters that are applied equally to all operations.
#   Can be overridden by:
#   * Associating a JSON-formatted list of key, value pairs to the `Plan`.
#   * Adding a JSON-formatted list of key, value pairs to an `Operation`
#     input of type JSON and named `Options`.
#
def default_job_params
  {
  }
end

# Default parameters that are applied to individual operations.
#   Can be overridden by:
#   * Adding a JSON-formatted list of key, value pairs to an `Operation`
#     input of type JSON and named `Options`.
#
def default_operation_params
  {
    shaker_parameters: { time: create_qty(qty: 1, units: MINUTES),
                         speed: create_qty(qty: 1600, units: RPM) },
    centrifuge_parameters: { time: create_qty(qty: 1, units: MINUTES),
                             speed: create_qty(qty: 500, units: TIMES_G) },
    incubation_params: { time: create_qty(qty: 5, units: MINUTES),
                         temperature: create_qty(qty: 'room temperature',
                                                 units: '') }
  }
end

  ########## MAIN ##########

  def main
    target_volume = 35 # ul
    target_molarity = 4 # nM
    @job_params = update_all_params(
      operations: operations,
      default_job_params: default_job_params,
      default_operation_params: default_operation_params
    )

    required_reactions = operations.length + 2

    operations.make

    retrieve_list = []

    operations.each_with_index do |op, idx|
      composition, consumables, _kit_ = setup_kit_composition(
        kit_sample_name: KIT_SAMPLE_NAME,
        num_reactions_required: create_qty(qty:required_reactions, units: 'rxn'),
        components: components,
        consumables: consumable_data
      )

      composition.input(RSB_HT).item = find_random_item(
        sample: composition.input(RSB_HT).sample,
        object_type: composition.input(RSB_HT).suggested_ot
      )

      composition.input(POOLED_LIBRARY).item = op.input(POOLED_LIBRARY).item

      adj_vol_list = reject_components(
        list_of_rejections: [POOLED_LIBRARY, MASTER_MIX, RSB_HT],
        components: composition.components
      )

      op.temporary[COMPOSITION_KEY] = [composition, consumables]

      adjust_volume(components: adj_vol_list,
                    multi: required_reactions)
      if idx == 0
        retrieve_list += reject_components(
          list_of_rejections: [POOLED_LIBRARY, MASTER_MIX],
          components: composition.components
        )
      end

      retrieve_list.append(composition.input(POOLED_LIBRARY))
      retrieve_list += consumables.consumables
    end

    first_composition, consumables = operations.first.temporary[COMPOSITION_KEY]
    mm_components = [first_composition.input(COMP_B),
                     first_composition.input(COMP_A)]

    show_block_1a = master_mix_handler(
      components: mm_components,
      mm: first_composition.input(MASTER_MIX),
      adjustment_multiplier: required_reactions,
      mm_container: consumables.input(TEST_TUBE)
    )

    show_retrieve_parts(retrieve_list)

    display_hash(
      title: 'Prepare Items',
      hash_to_show: [
        show_block_1a
      ]
    )

    sample_list = [consumables.input(QBIT_TUBE),
                   consumables.input(QBIT_TUBE)]
    label_list = ['s-1','s-2']

    operations.each do |op|
      comp, consumables = op.temporary[COMPOSITION_KEY]
      label_list.append("s-#{comp.input(POOLED_LIBRARY).item}")
      sample_list.append(consumables.input(QBIT_TUBE))
    end

    show_block_2a = label_items(
      objects: sample_list,
      labels: label_list
    )

    show_block_2b = pipet(volume: first_composition.input(MASTER_MIX).volume_hash,
                          source: first_composition.input(MASTER_MIX).display_name,
                          destination: label_list.join(', '))

    show_block_2c = pipet(volume: first_composition.input(COMP_C).volume_hash,
                          source: first_composition.input(MASTER_MIX).display_name,
                          destination: 's-1')

    show_block_2d = pipet(volume: first_composition.input(COMP_D).volume_hash,
                          source: first_composition.input(MASTER_MIX).display_name,
                          destination: 's-2')

    show_block_2e = []
    operations.each do |op|
      composition, consumables = op.temporary[COMPOSITION_KEY]

      show_block_2e.append(pipet(
        volume: composition.input(POOLED_LIBRARY).volume_hash,
        source: first_composition.input(POOLED_LIBRARY),
        destination: "s-#{composition.input(POOLED_LIBRARY).item}"
        ))
    end

    display_hash(
      title: 'Prepare Test',
      hash_to_show: [
        show_block_2a,
        show_block_2b,
        show_block_2c,
        show_block_2d,
        show_block_2e
      ]
    )

    sample_vol = qty_display(operations.first.temporary[COMPOSITION_KEY][0].input(POOLED_LIBRARY).volume_hash)
    concentrations = show do
      title 'Run Samples'
      note 'Go to and turn on Qubit'
      note "Press 'DNA' --> 'dsDNA' --> 'High Sensisitivity' --> 'Read Standards' "
      note "Insert <b>s-1</b> and press 'Read Standard'"
      note "Insert <b>s-2</b> and press 'Read Standard'"
      separator
      note "Press 'Run Samples'"
      note "Set volume to <b>#{sample_vol}"
      note "Set units to #{NANOGRAMS}/#{MICROLITERS}"
      note 'Place each sample in th Qubit and press "run"'
      operations.each do |op|
        get("number", var: op.id.to_s,
                      label: "Enter concentration in #{NANOGRAMS}/#{MICROLITERS}",
                      default: 0)
      end
    end

    operations.each do |op|
      composition, consumables = op.temporary[COMPOSITION_KEY]

      con = concentrations[op.id.to_s.to_sym]
      con = rand(0.97...3) if debug
      molarity = con * (10**6) / (600.0 * 400.0)
      if molarity < target_molarity
        inspect "Molarity #{molarity}, concentration: #{con}" if debug
        op.error(:molarity_too_low, 'Molarity too low')
        op.status = 'error'
        op.save
        next
      end

      volume_sample = target_molarity * target_volume / molarity
      volume_buffer = target_volume - volume_sample

      if debug
        inspect "samp: #{volume_sample}, buff: #{volume_buffer}, "\
                " concentration: #{con}"
      end

      show_block_3a = label_items(
        objects: [composition.input(MICRO_TUBE)],
        labels: [op.output(POOLED_LIBRARY).item]
      )

      show_block_3b = pipet(
        volume: create_qty(qty: volume_sample, units: MICROLITERS),
        source: composition.input(POOLED_LIBRARY),
        destination: op.output(POOLED_LIBRARY).item)

      show_block_3c = pipet(
        volume: create_qty(qty: volume_buffer, units: MICROLITERS),
        source: composition.input(RSB_HT),
        destination: op.output(POOLED_LIBRARY).item
      )

      display_hash(
        title: 'Dilute Library',
        hash_to_show: [
          show_block_3a,
          show_block_3b,
          show_block_3c
        ]
      )
    end

    {}
  end

end
