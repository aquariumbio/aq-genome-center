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
needs 'Composition Libs/CompositionHelper'

needs 'Collection Management/CollectionTransfer'
needs 'Collection Management/CollectionActions'

needs 'PCR Protocols/RunThermocycler'

needs 'Container/ItemContainer'
needs 'Container/KitHelper'
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
  include RunThermocycler
  include KitHelper
  include CovidSurveillanceHelper
  include KitContents
  include ConsumableDefinitions

  #========== Composition Definitions ==========#

  AREA_SEAL = "Microseal 'B' adhesive seals"
  FIRST_STRAND_KIT = 'Synthesize First Strand cDNA Kit'

  FSM_HT = 'First Strand Mix HT'
  RVT_HT = 'Reverse Transcriptase HT'

  MICRO_TUBES = '1.7 ml Reagent Tube'

  POOLED_PLATE = 'CDNA Sample Plate'
  MM_INPUT = 'FS CDNA Master Mix'

  def components
    [ 
       {
         input_name: POOLED_PLATE,
         qty: nil, units: MICROLITERS,
         sample_name: 'Pooled Specimens',
         suggested_ot: PLATE_384_WELL
       },
       {
         input_name: MM_INPUT,
         qty: 8, units: MICROLITERS,
         sample_name: MASTER_MIX,
         suggested_ot: MICRO_TUBES
       }
    ]
  end

  def consumable_data
    [
      {
        consumable: CONSUMABLES[AREA_SEAL],
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
    dragonfly_robot_program: 'FS CDNA MM',
    dragonfly_robot_model: Dragonfly::MODEL,
    storage_location: 'M80',
    shaker_parameters: { time: create_qty(qty: 1, units: MINUTES),
                         speed: create_qty(qty: 1600, units: RPM) },
    centrifuge_parameters: { time: create_qty(qty: 1, units: MINUTES),
                             speed: create_qty(qty: 1000, units: TIMES_G) },
    thermocycler_model: TestThermocycler::MODEL,
    program_name: 'duke_synthesize_fs',
    qpcr: true
  }
end

########## MAIN ##########

def main
  @job_params = update_all_params(
    operations: operations,
    default_job_params: default_job_params,
    default_operation_params: default_operation_params
  )

  operations.each do |op|

    op.pass(POOLED_PLATE)

    set_up_test(op) if debug
    temporary_options = op.temporary[:options]

    plate = op.input(POOLED_PLATE).collection

    required_reactions = create_qty(qty: plate.parts.length,
                                    units: 'rxn')

    composition, consumables, kits = setup_kit_composition(
      kit_sample_names: [FIRST_STRAND_KIT],
      num_reactions_required: required_reactions,
      components: components,
      consumables: consumable_data
    )

    kit = kits.first

    composition.set_adj_qty(plate.get_non_empty.length, extra: 0.005)

    composition.input(POOLED_PLATE).item = plate
    plate_display = composition.input(POOLED_PLATE).display_name

    retrieve_list = reject_components(
      list_of_rejections: [MM_INPUT, POOLED_PLATE],
      components: composition.components
    )

    display(
      title: 'Retrieve Materials',
      show_block: [retrieve_materials(retrieve_list + consumables.consumables,
                                      adj_qty: true)]
    )

    vortex_list = reject_components(
      list_of_rejections: [POOLED_PLATE],
      components: retrieve_list
    )

    show_block_1a = []
    show_block_1a.append(shake(items: vortex_list.map(&:display_name),
                               type: Vortex::NAME))

    adj_multiplier = plate.get_non_empty.length
    mm_components = [composition.input(FSM_HT),
                     composition.input(RVT_HT)]

    show_block_1b = master_mix_handler(
      components: mm_components,
      mm: composition.input(MM_INPUT),
      adjustment_multiplier: adj_multiplier,
      mm_container: composition.input(MICRO_TUBES)
    )

    display_hash(
      title: 'Prepare for Procedure',
      hash_to_show: [
        show_block_1a.flatten,
        show_block_1b.flatten
      ]
    )

    drgprogram = LiquidRobotProgramFactory.build(
      program_name: temporary_options[:dragonfly_robot_program]
    )

    drgrobot = LiquidRobotFactory.build(
      model: temporary_options[:dragonfly_robot_model],
      name: op.temporary[:robot_model],
      protocol: self
    )

    display_hash(
      title: 'Set Up and Run Robot',
      hash_to_show: use_robot(
        program: drgprogram,
        robot: drgrobot,
        items: [composition.input(MM_INPUT).display_name,
                plate_display]
      )
    )

    association_map = one_to_one_association_map(from_collection: plate)
    kit.remove_volume(required_reactions)
    associate_transfer_item_to_collection(
      from_item: composition.input(MM_INPUT).item,
      to_collection: plate,
      association_map: association_map,
      transfer_vol: composition.input(MM_INPUT).volume_hash
    )

    kit.remove_volume(required_reactions)

    show_block_3a = []
    show_block_3a.append(seal_plate(
      [plate_display], seal: consumables.input(AREA_SEAL)
    ))

    show_block_3b = []
    show_block_3b.append(shake(
      items: [plate_display],
      speed: temporary_options[:shaker_parameters][:speed],
      time: temporary_options[:shaker_parameters][:time]
    ))

    show_block_3c = []
    show_block_3c.append(spin_down(
      items: [plate_display],
      speed: temporary_options[:centrifuge_parameters][:speed],
      time: temporary_options[:centrifuge_parameters][:time]
    ))

    display_hash(
      title: 'Prepare for Thermocycler',
      hash_to_show: [
        show_block_3a.flatten,
        show_block_3b.flatten,
        show_block_3c.flatten
      ]
    )

    run_qpcr(op: op,
             plates: [composition.input(POOLED_PLATE)])

  end

  {}

end

def set_up_test(op)
  sample = op.input(POOLED_PLATE).part.sample
  plate = op.input(POOLED_PLATE).collection
  samples = Array.new(plate.get_empty.length, sample)
  plate.add_samples(samples)
end

end
