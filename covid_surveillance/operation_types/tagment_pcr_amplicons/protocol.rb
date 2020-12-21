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

needs 'PCR Protocols/RunThermocycler'

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
  include RunThermocycler
  include CovidSurveillanceHelper
  include KitContents

  COV1 = 'COV1'.freeze
  COV2 = 'COV2'.freeze
#========== Composition Definitions ==========#
  TAGMENT_KIT = 'Tagment PCR Amplicons Kit'

  EBLTS_HT = 'Enrichment BLT HT'
  TB1_HT = 'Tagmentation Buffer 1 HT'

  def components
    [
       {
         input_name: COV1,
         qty: 10, units: MICROLITERS,
         sample_name: 'Pooled Specimens',
         object_type: '96-Well Plate'
       },
       {
        input_name: COV2,
        qty: 10, units: MICROLITERS,
        sample_name: 'Pooled Specimens',
        object_type: '96-Well Plate'
      },
      {
        input_name: MASTER_MIX,
        qty: 30, units: MICROLITERS,
        sample_name: MASTER_MIX,
        object_type: TEST_TUBE
      },
      {
        input_name: WATER,
        qty: 20, units: MICROLITERS,
        sample_name: WATER,
        object_type: 'Reagent Bottle'
      }
    ]
  end

  def consumables
    [
      {
        input_name: AREA_SEAL,
        qty: 1, units: 'Each',
        description: 'Adhesive Plate Seal'
      },
      {
        input_name: TEST_TUBE,
        qty: 1, units: 'Each',
        description: TEST_TUBE
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
    mosquito_robot_program: 'Tagment PCR Amplicons',
    mosquito_robot_model: Mosquito::MODEL,
    dragonfly_robot_program: 'TAG_MM',
    dragonfly_robot_model: Dragonfly::MODEL,
    storage_location: 'M80',
    shaker_parameters: { time: create_qty(qty: 1, units: MINUTES),
                        speed: create_qty(qty: 1600, units: RPM) },
    centrifuge_parameters: { time: create_qty(qty: 1, units: MINUTES),
                            speed: create_qty(qty: 1000, units: TIMES_G) },
    thermocycler_model: TestThermocycler::MODEL,
    program_name: 'CDC_TaqPath_CG',
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

    operations.make

    operations.each do |op|
      set_up_test(op) if debug

      temporary_options = op.temporary[:options]

      required_reactions = create_qty(qty: op.input(COV1).collection.parts.length,
                                      units: 'rxn')

      composition, kit = setup_kit_composition(
        kit_sample_name: TAGMENT_KIT,
        num_reactions_required: required_reactions,
        components: components,
        consumables: consumables
      )

      composition.input(WATER).item = find_random_item(
        sample: composition.input(WATER).sample,
        object_type: composition.input(WATER).object_type
      )

      composition.input(COV1).item = op.input(COV1).collection
      composition.input(COV2).item = op.input(COV2).collection
      input_plate1 = composition.input(COV1).item
      input_plate2 = composition.input(COV2).item
      output_plate = op.output(POOLED_PLATE).collection

      retrieve_list = reject_components(
        list_of_rejections: [POOLED_PLATE, MASTER_MIX, COV1, COV2],
        components: composition.components
      )

      show_retrieve_parts(retrieve_list + composition.consumables)

      vortex_list = reject_components(
        list_of_rejections: [WATER, COV1, COV2, MASTER_MIX],
        components: retrieve_list
      )

      show_block_1a = shake(items: vortex_list,
                            type: Vortex::NAME)

      adj_multiplier = input_plate1.get_non_empty.length
      mm_components = [composition.input(EBLTS_HT),
                       composition.input(TB1_HT),
                       composition.input(WATER)]

      show_block_1b = master_mix_handler(components: mm_components,
                                         mm: composition.input(MASTER_MIX),
                                         adjustment_multiplier: adj_multiplier,
                                         mm_container: composition.input(TEST_TUBE))

      show_block_1b = []
      show_block_1b += label_items(
        objects: [composition.input(MICRO_TUBE).input_name],
        labels: [composition.input(MASTER_MIX).item]
      )

      show do
        title 'Prepare for Procedure'
        note show_block_1a.flatten
        separator
        note get_and_label_new_plate(output_plate)
        separator
        note show_block_1b.flatten
      end

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
        hash_to_show: use_robot(program: drgprogram,
                                robot: drgrobot,
                                items: [composition.input(MASTER_MIX), output_plate])
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
        hash_to_show: use_robot(program: program,
                                robot: robot, items: [input_plate1,
                                                      input_plate2,
                                                      output_plate])
      )

      association_map = one_to_one_association_map(from_collection: input_plate1)

      copy_wells(from_collection: input_plate1,
                to_collection: output_plate,
                association_map: association_map)

      associate_transfer_collection_to_collection(from_collection: input_plate1,
                                                  to_collection: output_plate,
                                                  association_map: association_map,
                                                  transfer_vol: composition.input(COV1).volume_hash)

      associate_transfer_collection_to_collection(from_collection: input_plate2,
                                                  to_collection: output_plate,
                                                  association_map: association_map,
                                                  transfer_vol: composition.input(COV2).volume_hash)
      mm = composition.input(MASTER_MIX)
      associate_transfer_item_to_collection(
        from_item: mm.item,
        to_collection: output_plate,
        association_map: association_map,
        transfer_vol: mm.volume_hash
      )

      kit.remove_volume(required_reactions)

      show_block_3a = []
      show_block_3a.append(seal_plate(
        [output_plate], seal: composition.input(AREA_SEAL).input_name
      ))

      show_block_3b = []
      show_block_3b.append(shake(
        items: [output_plate],
        speed: temporary_options[:shaker_parameters][:speed],
        time: temporary_options[:shaker_parameters][:time]
      ))

      show_block_3c = []
      show_block_3c.append(spin_down(
        items: [output_plate],
        speed: temporary_options[:centrifuge_parameters][:speed],
        time: temporary_options[:centrifuge_parameters][:time]
      ))

      show do
        title 'Prepare for Thermocycler'
        note show_block_3a.flatten
        separator
        note show_block_3b.flatten
        separator
        note show_block_3c.flatten
      end
      run_qpcr(op: op,
               plates: [output_plate])
    end

    {}

  end

  def set_up_test(op)
    sample1 = op.input(COV1).part.sample
    sample2 = op.input(COV2).part.sample
    plate1 = op.input(COV1).collection
    plate2 = op.input(COV2).collection
    samples1 = Array.new(plate1.get_non_empty.length, sample1)
    samples2 = Array.new(plate2.get_non_empty.length, sample2)

    plate1.add_samples(samples1)
    plate2.add_samples(samples2)
  end

end
