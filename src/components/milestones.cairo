use starknet::ContractAddress;
use starknet::storage::Vec;

#[derive(Serde, Drop)]
pub struct Milestone {
    pub title: ByteArray,
    pub description: ByteArray,
    pub payment: u256,
    pub deadline: u64,
    pub recipient: ContractAddress,
    pub completed: bool,
    pub parent_id: u64,
    pub children_ids: Array<u64>,
}

#[starknet::storage_node]
pub struct MilestoneStorageNode {
    pub title: ByteArray,
    pub description: ByteArray,
    pub payment: u256,
    pub deadline: u64,
    pub recipient: ContractAddress,
    pub completed: bool,
    pub parent_id: u64,
    pub children_ids: Vec<u64>,
}

#[derive(Serde, Drop, Clone)]
pub struct MilestoneMetadata {
    pub title: ByteArray,
    pub description: ByteArray,
    pub payment: u256,
    pub deadline: u64,
    pub recipient: ContractAddress,
}

#[starknet::interface]
pub trait IMilestones<TContractState> {
    fn get_milestone(self: @TContractState, milestone_id: u64) -> Option<Milestone>;
}

#[starknet::component]
pub mod MilestonesComponent {
    use core::num::traits::Zero;
    use starknet::get_block_timestamp;
    use starknet::storage::{
        Map, MutableVecTrait, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
        VecTrait,
    };
    use super::{Milestone, MilestoneMetadata, MilestoneStorageNode};

    pub const MAX_CHILDREN: u64 = 10;
    pub const MAX_DEPTH: u64 = 3;

    #[storage]
    pub struct Storage {
        Milestones_current_id: u64,
        Milestones_milestones: Map<u64, MilestoneStorageNode>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        MilestoneCreated: MilestoneCreated,
        MilestoneMetadataUpdated: MilestoneMetadataUpdated,
        MilestoneCompleted: MilestoneCompleted,
        MilestoneChildLinked: MilestoneChildLinked,
        MilestoneChildUnlinked: MilestoneChildUnlinked,
        MilestoneDeleted: MilestoneDeleted,
    }

    #[derive(Drop, starknet::Event)]
    pub struct MilestoneCreated {
        #[key]
        pub id: u64,
        pub metadata: MilestoneMetadata,
    }

    #[derive(Drop, starknet::Event)]
    pub struct MilestoneMetadataUpdated {
        #[key]
        pub id: u64,
        pub old_metadata: MilestoneMetadata,
        pub new_metadata: MilestoneMetadata,
    }

    #[derive(Drop, starknet::Event)]
    pub struct MilestoneChildLinked {
        #[key]
        pub parent_id: u64,
        #[key]
        pub child_id: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct MilestoneChildUnlinked {
        #[key]
        pub parent_id: u64,
        #[key]
        pub child_id: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct MilestoneDeleted {
        #[key]
        pub id: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct MilestoneCompleted {
        #[key]
        pub id: u64,
    }

    #[embeddable_as(MilestonesImpl)]
    impl Milestones<
        TContractState, +HasComponent<TContractState>,
    > of super::IMilestones<ComponentState<TContractState>> {
        fn get_milestone(
            self: @ComponentState<TContractState>, milestone_id: u64,
        ) -> Option<Milestone> {
            if !self.exists(milestone_id) {
                return None;
            }
            let node = self.Milestones_milestones.entry(milestone_id);
            let title = node.title.read();
            let description = node.description.read();
            let payment = node.payment.read();
            let deadline = node.deadline.read();
            let recipient = node.recipient.read();
            let completed = node.completed.read();
            let parent_id = node.parent_id.read();
            let mut children_ids = array![];
            for i in 0..node.children_ids.len() {
                children_ids.append(node.children_ids[i].read());
            }
            Some(
                Milestone {
                    title,
                    description,
                    payment,
                    deadline,
                    recipient,
                    completed,
                    parent_id,
                    children_ids,
                },
            )
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        fn current_id(self: @ComponentState<TContractState>) -> u64 {
            self.Milestones_current_id.read()
        }

        fn create(ref self: ComponentState<TContractState>, metadata: MilestoneMetadata) -> u64 {
            assert!(
                !metadata.recipient.is_zero(), "Milestone recipient cannot be the zero address",
            );
            assert!(
                metadata.deadline > get_block_timestamp(),
                "Milestone deadline must be in the future",
            );
            // 0 is sentinel for non-existent milestone, so start IDs from 1
            let milestone_id = self.Milestones_current_id.read() + 1;
            self.Milestones_current_id.write(milestone_id);
            let node = self.Milestones_milestones.entry(milestone_id);
            node.title.write(metadata.title.clone());
            node.description.write(metadata.description.clone());
            node.payment.write(metadata.payment);
            node.deadline.write(metadata.deadline);
            node.recipient.write(metadata.recipient);

            self.emit(MilestoneCreated { id: milestone_id, metadata });
            milestone_id
        }

        fn update_metadata(
            ref self: ComponentState<TContractState>,
            milestone_id: u64,
            new_metadata: MilestoneMetadata,
        ) {
            assert!(self.exists(milestone_id), "Milestone does not exist");
            assert!(!self.is_completed(milestone_id), "Cannot update completed milestone");
            assert!(
                !new_metadata.recipient.is_zero(), "Milestone recipient cannot be the zero address",
            );
            assert!(
                new_metadata.deadline > get_block_timestamp(),
                "Milestone deadline must be in the future",
            );
            let node = self.Milestones_milestones.entry(milestone_id);
            let old_metadata = MilestoneMetadata {
                title: node.title.read(),
                description: node.description.read(),
                payment: node.payment.read(),
                deadline: node.deadline.read(),
                recipient: node.recipient.read(),
            };
            node.title.write(new_metadata.title.clone());
            node.description.write(new_metadata.description.clone());
            node.payment.write(new_metadata.payment);
            node.deadline.write(new_metadata.deadline);
            node.recipient.write(new_metadata.recipient);

            self.emit(MilestoneMetadataUpdated { id: milestone_id, old_metadata, new_metadata });
        }

        fn link_child(ref self: ComponentState<TContractState>, parent_id: u64, child_id: u64) {
            assert!(self.exists(parent_id), "Parent milestone does not exist");
            assert!(self.exists(child_id), "Child milestone does not exist");
            assert!(!self.is_completed(parent_id), "Cannot link to completed parent milestone");
            assert!(!self.is_completed(child_id), "Cannot link completed child milestone");
            assert!(
                self.Milestones_milestones.entry(parent_id).children_ids.len() < MAX_CHILDREN,
                "Parent milestone has maximum number of children",
            );
            assert!(
                self.Milestones_milestones.entry(child_id).parent_id.read() == 0,
                "Child milestone already has a parent",
            );
            assert!(
                !self.is_ancestor(child_id, parent_id),
                "Cannot create circular milestone hierarchy",
            );
            assert!(
                self.depth(parent_id) + self.height(child_id) <= MAX_DEPTH,
                "Linking would exceed maximum milestone hierarchy depth",
            );

            let parent_node = self.Milestones_milestones.entry(parent_id);
            let child_node = self.Milestones_milestones.entry(child_id);
            parent_node.children_ids.push(child_id);
            child_node.parent_id.write(parent_id);

            self.emit(MilestoneChildLinked { parent_id, child_id });
        }

        fn unlink_child(ref self: ComponentState<TContractState>, parent_id: u64, child_id: u64) {
            assert!(self.exists(parent_id), "Parent milestone does not exist");
            assert!(self.exists(child_id), "Child milestone does not exist");
            assert!(!self.is_completed(parent_id), "Cannot unlink from completed parent milestone");
            assert!(!self.is_completed(child_id), "Cannot unlink completed child milestone");
            assert!(
                self.is_child(child_id, parent_id), "Parent milestone does not contain this child",
            );

            let parent_node = self.Milestones_milestones.entry(parent_id);
            let child_node = self.Milestones_milestones.entry(child_id);
            child_node.parent_id.write(0);
            if (parent_node.children_ids.len() == 1) {
                let _ = parent_node.children_ids.pop();
            } else {
                // Replace with last and pop to avoid shifting all elements
                let last_option = parent_node.children_ids.pop();
                if let Some(last_child_id) = last_option {
                    if last_child_id != child_id {
                        for i in 0..parent_node.children_ids.len() {
                            if parent_node.children_ids[i].read() == child_id {
                                parent_node.children_ids[i].write(last_child_id);
                                break;
                            }
                        }
                    }
                }
            }

            self.emit(MilestoneChildUnlinked { parent_id, child_id });
        }

        fn complete(ref self: ComponentState<TContractState>, milestone_id: u64) {
            assert!(self.exists(milestone_id), "Milestone does not exist");
            let node = self.Milestones_milestones.entry(milestone_id);
            assert!(!self.is_completed(milestone_id), "Milestone is already completed");
            for i in 0..node.children_ids.len() {
                let child_id = node.children_ids[i].read();
                assert!(
                    self.is_completed(child_id),
                    "Cannot complete milestone with incomplete children",
                );
            }
            assert!(
                node.deadline.read() >= get_block_timestamp(),
                "Cannot complete milestone past its deadline",
            );
            node.completed.write(true);

            self.emit(MilestoneCompleted { id: milestone_id });
        }

        fn delete(ref self: ComponentState<TContractState>, milestone_id: u64) {
            assert!(self.exists(milestone_id), "Milestone does not exist");
            let node = self.Milestones_milestones.entry(milestone_id);
            assert!(!self.is_completed(milestone_id), "Cannot delete completed milestone");
            for i in 0..node.children_ids.len() {
                let child_id = node.children_ids[i].read();
                assert!(
                    !self.is_completed(child_id), "Cannot delete milestone with completed children",
                );
            }

            if (node.parent_id.read() != 0) {
                self.unlink_child(node.parent_id.read(), milestone_id);
            }

            let len = node.children_ids.len();
            // To prevent incorrect reads after mutations
            let mut children_snapshot: Array<u64> = array![];
            for i in 0..len {
                children_snapshot.append(node.children_ids[i].read());
            }
            for child_id in children_snapshot {
                self.unlink_child(milestone_id, child_id);
            }

            node.title.write("");
            node.description.write("");
            node.payment.write(0);
            node.deadline.write(0);
            node.recipient.write(0.try_into().unwrap());
            node.completed.write(false);
            node.parent_id.write(0);

            self.emit(MilestoneDeleted { id: milestone_id });
        }

        fn is_ancestor(
            self: @ComponentState<TContractState>, ancestor_id: u64, descendant_id: u64,
        ) -> bool {
            let mut current_id = descendant_id;
            while current_id != 0 {
                if current_id == ancestor_id {
                    return true;
                }
                let node = self.Milestones_milestones.entry(current_id);
                current_id = node.parent_id.read();
            }
            false
        }

        fn is_child(self: @ComponentState<TContractState>, child_id: u64, parent_id: u64) -> bool {
            let parent_node = self.Milestones_milestones.entry(parent_id);
            for i in 0..parent_node.children_ids.len() {
                if parent_node.children_ids[i].read() == child_id {
                    return true;
                }
            }
            false
        }

        fn is_completed(self: @ComponentState<TContractState>, milestone_id: u64) -> bool {
            let node = self.Milestones_milestones.entry(milestone_id);
            node.completed.read()
        }

        fn all_completed(self: @ComponentState<TContractState>) -> bool {
            let mut milestone_id = 1;
            let current_id = self.Milestones_current_id.read();
            while milestone_id <= current_id {
                if self.exists(milestone_id) && !self.is_completed(milestone_id) {
                    return false;
                }
                milestone_id += 1;
            };
            true
        }

        fn exists(self: @ComponentState<TContractState>, milestone_id: u64) -> bool {
            let node = self.Milestones_milestones.entry(milestone_id);
            // A milestone must always have a deadline > 0 and 0 < ID <= current_id
            node.deadline.read() > 0
                && milestone_id > 0
                && milestone_id <= self.Milestones_current_id.read()
        }

        fn depth(self: @ComponentState<TContractState>, milestone_id: u64) -> u64 {
            let mut depth = 0;
            let mut current_id = milestone_id;
            while current_id != 0 {
                depth += 1;
                let node = self.Milestones_milestones.entry(current_id);
                current_id = node.parent_id.read();
            }
            depth
        }

        fn height(self: @ComponentState<TContractState>, milestone_id: u64) -> u64 {
            let node = self.Milestones_milestones.entry(milestone_id);
            if (node.children_ids.len() == 0) {
                return 1;
            }
            let mut max_child_height = 0;
            for i in 0..node.children_ids.len() {
                let child_id = node.children_ids[i].read();
                let child_height = self.height(child_id);
                if (child_height > max_child_height) {
                    max_child_height = child_height;
                }
            }
            max_child_height + 1
        }
    }
}
