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

# ============= Composition Definitions -==============#

  AMPLIFY_KIT = 'Amplify cDNA Kit'

  MASTER_MIX_1 = 'PCR Master Mix 1'
  MASTER_MIX_2 = 'PCR Master Mix 2'
  POOLED_PLATE = 'CDNA Sample Plate'

  def components
    [ 
       {
         input_name: POOLED_PLATE,
         qty: 5, units: MICROLITERS,
         sample_name: 'Pooled Specimens'
       },
       {
         input_name: MASTER_MIX_1,
         qty: 20, units: MICROLITERS,
         sample_name: MASTER_MIX,
         suggested_ot: TUBE_5ML
       },
       {
        input_name: MASTER_MIX_2,
        qty: 20, units: MICROLITERS,
        sample_name: MASTER_MIX,
        suggested_ot: TUBE_5ML
       },
       {
        input_name: COV1,
        qty: nil, units: MICROLITERS,
        sample_name: 'Pooled Specimens'
      },
      {
        input_name: COV2,
        qty: nil, units: MICROLITERS,
        sample_name: 'Pooled Specimens'
      },
      {
        input_name: WATER,
        qty: 3.91, units: MICROLITERS,
        sample_name: WATER,
        suggested_ot: 'Reagent Bottle'
      }
    ]
  end

  def consumable_data
    [
      {
        consumable: CONSUMABLES[AREA_SEAL],
        qty: 1, units: 'Each'
      },
      {
        consumable: CONSUMABLES[TUBE_5ML],
        qty: 2, units: 'Each'
      },
      {
        consumable: CONSUMABLES[PLATE_384_WELL],
        qty: 2, units: 'Each'
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
    mosquito_robot_program: 'Amplify CDNA',
    mosquito_robot_model: Mosquito::MODEL,
    dragonfly_robot_program: 'PCR 1 MM',
    dragonfly_robot_program2: 'PCR 2 MM',
    dragonfly_robot_model: Dragonfly::MODEL,
    storage_location: 'M80',
    shaker_parameters: { time: create_qty(qty: 1, units: MINUTES),
                         speed: create_qty(qty: 1600, units: RPM) },
    centrifuge_parameters: { time: create_qty(qty: 1, units: MINUTES),
                             speed: create_qty(qty: 1000, units: TIMES_G) },
    thermocycler_model: TestThermocycler::MODEL,
    program_name: 'duke_amplify_cdna',
    qpcr: true
  }
end

COV1 = 'COV1'.freeze
COV2 = 'COV2'.freeze

########## MAIN ##########

  def main
    @job_params = update_all_params(
      operations: operations,
      default_job_params: default_job_params,
      default_operation_params: default_operation_params
    )

    operations.make

    operations.each do |op|
      set_up_test(op) if debug

      temporary_options = op.temporary[:options]

      required_reactions = create_qty(qty: op.input(POOLED_PLATE).collection.parts.length,
                                      units: 'rxn')

      composition, consumables, kits = setup_kit_composition(
        kit_sample_names: [AMPLIFY_KIT],
        num_reactions_required: required_reactions,
        components: components,
        consumables: consumable_data
      )

      kit = kits.first

      composition.input(WATER).item = find_random_item(
        sample: composition.input(WATER).sample,
        object_type: composition.input(WATER).suggested_ot
      )

      composition.input(POOLED_PLATE).item = op.input(POOLED_PLATE).collection
      composition.input(COV1).item = op.output(COV1).collection
      composition.input(COV2).item = op.output(COV2).collection
      input_plate = composition.input(POOLED_PLATE).item
      plate1 = composition.input(COV1).item
      plate2 = composition.input(COV2).item

      retrieve_list = reject_components(
        list_of_rejections: [POOLED_PLATE, COV1, COV2,
                             MASTER_MIX_1, MASTER_MIX_2],
        components: composition.components
      )

      composition.set_adj_qty(
        composition.input(POOLED_PLATE).item.get_non_empty.length,
        extra: 0.005
      )

      display(
        title: 'Retrieve the Following Materials',
        show_block: retrieve_materials(retrieve_list + consumables.consumables,
                                       adj_qty: true)
      )

      vortex_list = reject_components(
        list_of_rejections: [POOLED_PLATE, WATER],
        components: retrieve_list
      )

      show_block_1a = shake(items: vortex_list.map(&:display_name),
                            type: Inversion::NAME)

      adj_multiplier = plate1.get_non_empty.length
      mm_components_1 = [composition.input(IPM_HT),
                         composition.input(CPP1_HT),
                         composition.input(WATER)]
      mm_components_2 = [composition.input(IPM_HT),
                         composition.input(CPP2_HT),
                         composition.input(WATER)]

      show_block_1b = master_mix_handler(components: mm_components_1,
                                         mm: composition.input(MASTER_MIX_1),
                                         adjustment_multiplier: adj_multiplier,
                                         mm_container: composition.input(TEST_TUBE))

      show_block_1c = master_mix_handler(components: mm_components_2,
                                         mm: composition.input(MASTER_MIX_2),
                                         adjustment_multiplier: adj_multiplier,
                                         mm_container: composition.input(TEST_TUBE))

      display_hash(
        title: 'Prepare for Procedure',
        hash_to_show: [
          show_block_1a,
          show_block_1b,
          show_block_1c,
          get_and_label_new_item(composition.input(COV1)),
          get_and_label_new_item(composition.input(COV2))
        ]
      )

      drgprogram = LiquidRobotProgramFactory.build(
        program_name: temporary_options[:dragonfly_robot_program]
      )
      drgprogram2 = LiquidRobotProgramFactory.build(
        program_name: temporary_options[:dragonfly_robot_program2]
      )

      drgrobot = LiquidRobotFactory.build(
        model: temporary_options[:dragonfly_robot_model],
        name: op.temporary[:robot_model],
        protocol: self
      )
      display_hash(
        title: 'Set Up and Run Robot',
        hash_to_show: use_robot(program: drgprogram,
                                robot: drgrobot,
                                items: [composition.input(COV1).display_name,
                                        composition.input(MASTER_MIX_1).display_name])
      )

      display_hash(
        title: 'Set Up and Run Robot',
        hash_to_show: use_robot(program: drgprogram2,
                                robot: drgrobot,
                                items: [composition.input(COV2).display_name,
                                        composition.input(MASTER_MIX_2).display_name])
      )

      program = LiquidRobotProgramFactory.build(
        program_name: temporary_options[:mosquito_robot_program]
      )

      robot = LiquidRobotFactory.build(
        model: temporary_options[:mosquito_robot_model],
        name: op.temporary[:robot_model],
        protocol: self
      )

      display_hash(
        title: 'Set Up and Run Robot',
        hash_to_show: use_robot(
          program: program,
          robot: robot, items: [composition.input(POOLED_PLATE),
                                composition.input(COV1).display_name,
                                composition.input(COV2).display_name,
                                'Waste Plate'])
      )

      association_map = one_to_one_association_map(from_collection: input_plate)

      copy_wells(from_collection: input_plate,
                 to_collection: plate1,
                 association_map: association_map)

      copy_wells(from_collection: input_plate,
                 to_collection: plate2,
                 association_map: association_map)

      associate_transfer_item_to_collection(
        from_item: composition.input(MASTER_MIX_1).item,
        to_collection: plate1,
        association_map: association_map,
        transfer_vol: composition.input(MASTER_MIX_1).volume_hash
      )

      associate_transfer_collection_to_collection(
        from_collection: input_plate,
        to_collection: plate1,
        association_map: association_map,
        transfer_vol: composition.input(POOLED_PLATE).volume_hash
      )

      associate_transfer_item_to_collection(
        from_item: composition.input(MASTER_MIX_2).item,
        to_collection: plate2,
        association_map: association_map,
        transfer_vol: composition.input(MASTER_MIX_2).volume_hash
      )

      associate_transfer_collection_to_collection(from_collection: input_plate,
                                                  to_collection: plate2,
                                                  association_map: association_map,
                                                  transfer_vol: composition.input(POOLED_PLATE).volume_hash)

      kit.remove_volume(required_reactions)

      show_block_3a = []
      show_block_3a.append(seal_plate(
        [composition.input(COV1).display_name,
         composition.input(COV2).display_name], seal: consumables.input(AREA_SEAL)
      ))

      show_block_3b = []
      show_block_3b.append(shake(
        items: [composition.input(COV1).display_name,
                composition.input(COV2).display_name],
        speed: temporary_options[:shaker_parameters][:speed],
        time: temporary_options[:shaker_parameters][:time]
      ))

      show_block_3c = []
      show_block_3c.append(spin_down(
        items: [composition.input(COV1).display_name,
                composition.input(COV2).display_name],
        speed: temporary_options[:centrifuge_parameters][:speed],
        time: temporary_options[:centrifuge_parameters][:time]
      ))

      display_hash(
        title: 'Prepare for Thermocycler',
        hash_to_show: [
          show_block_3a,
          show_block_3b,
          show_block_3c
        ]
      )

      run_qpcr(op: op,
               plates: [composition.input(COV1).item, composition.input(COV2).item])

      display(
        title: 'Safe Stopping Point',
        show_block: [{ display: "<b>Safe Stopping Point</b> If you are stopping, seal #{composition.input(COV1)}, #{composition.input(COV2)} and store at -25C to -15C for up to 3 days",
                       type: 'note' }]
      )
    end

    {}

  end

  def set_up_test(op)
    sample = op.input(POOLED_PLATE).part.sample
    plate = op.input(POOLED_PLATE).collection
    samples = Array.new(plate.get_non_empty.length, sample)
    plate.add_samples(samples)
  end
end
