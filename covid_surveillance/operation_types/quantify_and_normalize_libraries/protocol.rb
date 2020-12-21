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

needs 'CompositionLibs/AbstractComposition'
needs 'CompositionLibs/CompositionHelper'

needs 'Collection Management/CollectionTransfer'
needs 'Collection Management/CollectionActions'

needs 'Kits/KitContents'

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
        object_type: nil,
        notes: 'na'
      },
      {
        input_name: MASTER_MIX,
        qty: 180, units: MICROLITERS,
        sample_name: MASTER_MIX,
        object_type: 'Reagent Bottle',
        notes: 'na'
     },
     {
      input_name: RSB_HT,
      qty: nil, units: MICROLITERS,
      sample_name: 'nil',
      object_type: 'Reagent Bottle',
      notes: 'Thaw and Keep on Ice'
    },
    ]
  end

  def consumables
    [
      {
        input_name: TEST_TUBE,
        qty: 1, units: 'Each',
        description: TEST_TUBE
      },
      {
        input_name: MICRO_TUBE,
        qty: 1, units: 'Each',
        description: MICRO_TUBE
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
      composition, _kit_ = setup_kit_composition(
        kit_sample_name: KIT_SAMPLE_NAME,
        num_reactions_required: create_qty(qty:required_reactions, units: 'rxn'),
        components: components,
        consumables: consumables
      )

      composition.input(POOLED_LIBRARY).item = op.input(POOLED_LIBRARY).item

      adj_vol_list = reject_components(
        list_of_rejections: [POOLED_LIBRARY, MASTER_MIX, RSB_HT],
        components: composition.components
      )

      op.temporary[COMPOSITION_KEY] = composition

      adjust_volume(components: adj_vol_list,
                    multi: required_reactions)
      if idx == 0
        retrieve_list += reject_components(
          list_of_rejections: [POOLED_LIBRARY, MASTER_MIX],
          components: composition.components
        )
      end

      retrieve_list.append(composition.input(POOLED_LIBRARY))
      retrieve_list += composition.consumables
    end

    show_retrieve_parts(retrieve_list)

    first_composition = operations.first.temporary[COMPOSITION_KEY]
    mm_components = [first_composition.input(COMP_B),
                     first_composition.input(COMP_A)]

    show_block_1a = master_mix_handler(
      components: mm_components,
      mm: first_composition.input(MASTER_MIX),
      adjustment_multiplier: required_reactions,
      mm_container: first_composition.input(TEST_TUBE)
    )

    show do
      title 'Prepare Items'
      note show_block_1a
    end

    sample_list = [first_composition.input(QBIT_TUBE),
                   first_composition.input(QBIT_TUBE)]
    label_list = ['s-1','s-2']

    operations.each do |op|
      comp = op.temporary[COMPOSITION_KEY]
      label_list.append("s-#{comp.input(POOLED_LIBRARY).item}")
      sample_list.append(comp.input(QBIT_TUBE))
    end

    show_block_2a = label_items(
      objects: sample_list,
      labels: label_list
    )

    show_block_2b = pipet(volume: first_composition.input(MASTER_MIX).volume_hash,
                          source: first_composition.input(MASTER_MIX),
                          destination: label_list.to_s)

    show_block_2c = pipet(volume: first_composition.input(COMP_C).volume_hash,
                          source: first_composition.input(MASTER_MIX),
                          destination: 's-1')

    show_block_2d = pipet(volume: first_composition.input(COMP_D).volume_hash,
                          source: first_composition.input(MASTER_MIX),
                          destination: 's-2')

    show_block_2e = []
    operations.each do |op|
      composition = op.temporary[COMPOSITION_KEY]

      show_block_2e.append(pipet(
        volume: composition.input(POOLED_LIBRARY).volume_hash,
        source: first_composition.input(POOLED_LIBRARY),
        destination: "s-#{composition.input(POOLED_LIBRARY).item}"
        ))
    end

    show do
      title 'Prepare Test'
      note show_block_2a
      separator
      note show_block_2b
      separator
      note show_block_2c
      separator
      note show_block_2d
      separator
      note show_block_2e
    end
    sample_vol = qty_display(operations.first.temporary[COMPOSITION_KEY].input(POOLED_LIBRARY).volume_hash)
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
        composition = op.temporary[COMPOSITION_KEY]
        get("number", var: composition.input(POOLED_LIBRARY).item.id.to_s, 
                      label: "Enter concentration in #{NANOGRAMS}/#{MICROLITERS}",
                      default: '')
      end
    end

    operations.each do |op|
      composition = op.temporary[COMPOSITION_KEY]
      con = concentrations[composition.input(POOLED_LIBRARY).item.id.to_s]
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
        destination: op.output(POOLED_LIBRARY).item)
 
      show do 
        title 'Dilute Library'
        note show_block_3a
        separator
        note show_block_3b
        separator
        note show_block_3c
      end
    end

    {}
  end

end
