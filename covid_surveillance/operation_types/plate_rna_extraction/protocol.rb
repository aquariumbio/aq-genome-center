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
needs 'Liquid Robot Helper/RobotHelper'

needs 'CompositionLibs/AbstractComposition'
needs 'CompositionLibs/CompositionHelper'

needs 'Collection Management/CollectionTransfer'
needs 'Collection Management/CollectionActions'


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

  # ============= Composition Definitions ==============#
  EXTRACTION_KIT = 'QiAmp 96 Viral RNA Kit'

  AREA_SEAL = "AirPore Tape Sheet"
  TAPE_PAD = 'Tape Pad'

  ETHANOL = 'Absolute ethanol'

  DEEP_WELL_PLATE = '96 Well Deepwell Plate 2 ml'
  QIAAMP_PLATE = 'QIAamp 96 Plate'

  AVL = 'Buffer AVL'
  AW1 = 'Buffer AW1'
  AW2 = 'Buffer AW2'
  AVE = 'Buffer AVE'
  CARRIER = 'Carrier RNA'
  ELUTE = 'TopElute Fluid'

  AVL_AVE_CARRIER = 'Mixed Carrier RNA, AVE, AVL'

  EXTRACTION_PLATE = 'Extracted Sample Plate'

  def components
    [ 
       {
         input_name: POOLED_PLATE,
         qty: 140, units: MICROLITERS,
         sample_name: 'Pooled Specimens',
         object_type: '96-Well Plate'
       },
       {
         input_name: ETHANOL,
         qty: 560, units: MICROLITERS,
         sample_name: ETHANOL,
         object_type: 'Reagent Bottle'
       },
       {
        input_name: AVL_AVE_CARRIER,
        qty: 560, units: MICROLITERS,
        sample_name: AVL_AVE_CARRIER,
        object_type: 'Reagent Bottle'
      },
      {
        input_name: EXTRACTION_PLATE,
        qty: nil, units: nil,
        sample_name: 'Pooled Specimens',
        object_type: '96-Well Plate'
      },
      {
        input_name: DEEP_WELL_PLATE,
        qty: 630, units: MICROLITERS,
        sample_name: 'Pooled Specimens',
        object_type: DEEP_WELL_PLATE
      },
      {
        input_name: QIAAMP_PLATE,
        qty: nil, units: nil,
        sample_name: 'Pooled Specimens',
        object_type: QIAAMP_PLATE
      },
    ]
  end

  def consumables
    [
      {
        input_name: '96 Well Deepwell Plate',
        qty: 2, units: 'Each',
        description: DEEP_WELL_PLATE
      },
      {
        input_name: '96 Well Plate',
        qty: 2, units: 'Each',
        description: MICROLITERS
      },
      {
        input_name: TAPE_PAD,
        qty: 1, units: 'Each',
        description: TAPE_PAD
      }
    ]
  end

  def kits
    [
      {
        input_name: EXTRACTION_KIT,
        qty: 1, units: 'kits',
        description: EXTRACTION_KIT,
        location: 'Room Temperature Location TBD',
        components: [
          {
            input_name: AVL,
            qty: 560, units: MICROLITERS,
            sample_name: AVL,
            object_type: 'Reagent Bottle'
          },
          {
            input_name: AW1,
            qty: 500, units: MICROLITERS,
            sample_name: AW1,
            object_type: 'Reagent Bottle'
          },
          {
            input_name: AW2,
            qty: 500, units: MICROLITERS,
            sample_name: AW2,
            object_type: 'Reagent Bottle'
          },
          {
            input_name: AVE,
            qty: 80, units: MICROLITERS,
            sample_name: AVE,
            object_type: 'Reagent Bottle'
          },
          {
            input_name: ELUTE,
            qty: nil, units: MICROLITERS,
            sample_name: ELUTE,
            object_type: 'Reagent Bottle'
          },
          {
            input_name: CARRIER,
            qty: 60, units: MICROLITERS,
            sample_name: CARRIER,
            object_type: 'Reagent Bottle'
          }
        ],
        consumables: [
          {
            input_name: QIAAMP_PLATE,
            qty: 10, units: 'Each',
            description: QIAAMP_PLATE
          }
        ]
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
      centrifuge_parameters: { time: create_qty(qty: 4, units: MINUTES),
                               speed: create_qty(qty: 5788, units: TIMES_G) },
      incubation_params: { time: create_qty(qty: 10, units: MINUTES),
                           temperature: create_qty(qty: 'room temperature',
                                                   units: '') }
    }
  end

  # Default parameters that are applied to individual operations.
  #   Can be overridden by:
  #   * Adding a JSON-formatted list of key, value pairs to an `Operation`
  #     input of type JSON and named `Options`.
  #
  def default_operation_params
    {
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
    set_up_test(operations)

    operations.each do |op|
      composition = CompositionFactory.build(components: components,
                                             consumables: consumables,
                                             kits: kits)
      op.temporary[:composition] = composition
      composition.make_kit_component_items
      composition.input(ETHANOL).item = find_random_item(
        sample: composition.input(ETHANOL).sample,
        object_type: composition.input(ETHANOL).object_type
      )
      composition.input(POOLED_PLATE).item = op.input(POOLED_PLATE).collection
      show_retrieve_components([composition.input(POOLED_PLATE), composition.input(ETHANOL)])
      show_retrieve_consumables(composition.consumables)
      show_retrieve_kits(composition.kits)
    end

    prep_carrier_rna(operations: operations)

    dilute_buffer(operations: operations, input: AW1)

    dilute_buffer(operations: operations, input: AW2)

    copy_and_add_item_to_all(operations: operations,
                             to_name: DEEP_WELL_PLATE,
                             from_name: POOLED_PLATE,
                             from_item: AVL_AVE_CARRIER)

    seal_plate(operations.map{ |op| op.temporary[:composition].input(DEEP_WELL_PLATE).item },
               seal: operations.first.temporary[:composition].input(TAPE_PAD).input_name)

    show_incubate_items(
      items: operations.map { |op| op.temporary[:composition].input(DEEP_WELL_PLATE).item },
      time: { qty: 10, units: MINUTES },
      temperature: default_job_params[:incubation_params][:temperature]
    )

    add_item_to_all(operations: operations,
                    to_name: DEEP_WELL_PLATE,
                    from_name: ETHANOL)

    2.times do 
      copy_and_add_item_to_all(operations: operations,
                              to_name: QIAAMP_PLATE,
                              from_name: DEEP_WELL_PLATE,
                              sblock: true)

      seal_plate(operations.map{ |op| op.temporary[:composition].input(QIAAMP_PLATE).item },
                 seal: operations.first.temporary[:composition].input(TAPE_PAD).input_name)

      spin_down(
        items: operations.map{ |op| op.temporary[:composition].input(QIAAMP_PLATE).item},
        speed: default_job_params[:centrifuge_parameters][:speed],
        time: { qty: 4, units: MINUTES },
        type: 'QIAGEN 4-16KS Centrifuge'
      )
    end

    place_on_sblock(operations, QIAAMP_PLATE)

    add_item_to_all(operations: operations, to_name: QIAAMP_PLATE, from_name: AW1)

    seal_plate(operations.map{ |op| op.temporary[:composition].input(QIAAMP_PLATE).item },
               seal: operations.first.temporary[:composition].input(TAPE_PAD).input_name)

    spin_down(
      items: operations.map{ |op| op.temporary[:composition].input(QIAAMP_PLATE).item },
      speed: default_job_params[:centrifuge_parameters][:speed],
      time: { qty: 4, units: MINUTES },
      type: 'QIAGEN 4-16KS Centrifuge'
    )

    add_item_to_all(operations: operations, to_name: QIAAMP_PLATE, from_name: ETHANOL)

    seal_plate(operations.map{ |op| op.temporary[:composition].input(QIAAMP_PLATE).item },
               seal: operations.first.temporary[:composition].input(TAPE_PAD).input_name)

    spin_down(
      items: operations.map{ |op| op.temporary[:composition].input(QIAAMP_PLATE).item },
      speed: default_job_params[:centrifuge_parameters][:speed],
      time: { qty: 5, units: MINUTES },
      type: 'QIAGEN 4-16KS Centrifuge'
    )

    place_on_sblock(operations, QIAAMP_PLATE)

    spin_down(
      items: operations.map{ |op| op.temporary[:composition].input(QIAAMP_PLATE).item },
      speed: default_job_params[:centrifuge_parameters][:speed],
      time: { qty: 10, units: MINUTES },
      type: 'QIAGEN 4-16KS Centrifuge'
    )

    tab = [['QIAamp 96 Plate ID', 'Clean Elution Plate ID']]
    operations.each do |op|
      composition = op.temporary[:composition]

      extraction_comp = composition.input(EXTRACTION_PLATE)
      extraction_comp.item = get_and_label_new_plate(op.output(EXTRACTION_PLATE).collection)
      from_comp = composition.input(QIAAMP_PLATE)
      map = one_to_one_association_map(from_collection: from_comp.item)
      copy_wells(from_collection: from_comp.item,
                 to_collection: extraction_comp.item,
                 association_map: map)
      tab.append([from_comp.item.to_s, extraction_comp.item.to_s])
    end

    show do
      title 'Place QIAamp 96 Plate on Elution Plate'
      note 'Please place each QIAamp 96 Plate on a clean Elution Plate'
      table tab
    end

    add_item_to_all(operations: operations, to_name: QIAAMP_PLATE, from_name: AVE)

    spin_down(
      items: operations.map{ |op| op.temporary[:composition].input(QIAAMP_PLATE).item },
      speed: default_job_params[:centrifuge_parameters][:speed],
      time: { qty: 4, units: MINUTES },
      type: 'QIAGEN 4-16KS Centrifuge'
    )

    seal_plate(operations.map{ |op| op.temporary[:composition].input(QIAAMP_PLATE).item },
               seal: operations.first.temporary[:composition].input(TAPE_PAD).input_name)

    {}
  end

  def add_item_to_all(operations:, to_name:, from_name:)
    operations.each do |op|
      composition = op.temporary[:composition]
      map = one_to_one_association_map(from_collection: composition.input(to_name).item)
      source = composition.input(from_name)
      source = composition.input(EXTRACTION_KIT).input(from_name) unless source.present?

      destination = composition.input(to_name)
      destination = composition.input(EXTRACTION_KIT).input(to_name) unless destination.present?

      multichannel_item_to_collection(
        source: source.item,
        to_collection: destination.item,
        association_map: map,
        volume: source.volume_hash
      )
    end
  end

  def copy_and_add_item_to_all(operations:, to_name:, from_name:,
                               from_item: nil, sblock: false)
    operations.each do |op|
      composition = op.temporary[:composition]

      deep_plate = composition.input(to_name)
      deep_plate.item = make_new_plate(deep_plate.object_type)
      place_on_sblock([op], to_name) if sblock
      input_plate = composition.input(from_name).item
      map = one_to_one_association_map(from_collection: input_plate)
      copy_wells(from_collection: input_plate,
                 to_collection: deep_plate.item,
                 association_map: map)
      if from_item.present?
        multichannel_item_to_collection(
          source: composition.input(from_item).item,
          to_collection: deep_plate.item,
          association_map: map,
          volume: composition.input(from_item).volume_hash
        )
      end

      multichannel_collection_to_collection(
        from_collection: input_plate,
        to_collection: deep_plate.item,
        association_map: map,
        volume: composition.input(from_name).volume_hash
      )
    end
  end

  def place_on_sblock(ops, comp_name)
    show do 
      title "Place on #{ops.first.temporary[:composition].input('96 Well Deepwell Plate').input_name}"
      ops.each do |op|
        comp = op.temporary[:composition]
        note "Place <b>#{comp.input(comp_name).item}</b> on a new <b>#{comp.input('96 Well Deepwell Plate').input_name}</b>"
      end
    end
  end

  # Directions to dilute buffers
  #
  # @param 
  def dilute_buffer(operations:, input:)
    operations.each do |op|
      component = op.temporary[:composition].input(EXTRACTION_KIT).input(input)
      ethanol = op.temporary[:composition].input(ETHANOL)
      show do
        title 'Dilute Buffer Concentrate'
        note "Add appropriate amount of ethanol <b>#{ethanol.item}</b> to <b>#{component.input_name} #{component.item}</b>"
      end
    end
  end

  # directions to prep the carrier RNA
  #
  # @param operations [OperationList] list of operations
  def prep_carrier_rna(operations:)
    operations.each do |op|
      composition = op.temporary[:composition]
      num_samples = composition.input(POOLED_PLATE).item.get_non_empty.length
      kit = composition.input(EXTRACTION_KIT)
      kit.input(AVE).adj_qty = 1550 # TODO Encode this somewhere not hard coded

      mix = composition.input(AVL_AVE_CARRIER)
      avl = kit.input(AVL)
      carrier = kit.input(AVL)

      create_master_mix(components: [kit.input(AVE)],
                        master_mix_item: carrier.item,
                        adj_qty: true)

      mix.item = make_item(
        sample: mix.sample,
        object_type: mix.object_type
      )

      avl.adj_qty = num_samples * 600
      carrier.adjusted_qty(num_samples)

      create_master_mix(components: [avl, carrier],
                        master_mix_item: mix.item,
                        adj_qty: true,
                        vortex: false)
      show do
        title 'Mix by Inversion'
        note "Gently mix #{mix.item} by inverting tube 10 times"
      end
    end
  end

  def set_up_test(operations)
    operations.each do |op|
      sample = op.input(POOLED_PLATE).part.sample
      plate = op.input(POOLED_PLATE).collection
      samples = Array.new(20, sample)
      plate.add_samples(samples)
    end
  end
end
